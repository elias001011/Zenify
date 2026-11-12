import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:musify/services/download_manager.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'support/app_harness.dart';

void main() {
  final manager = DownloadManager.instance;

  useAppSettings(boxes: ['userNoBackup', 'settings']);

  setUp(() {
    manager
      ..idleMargin = const Duration(milliseconds: 20)
      ..reset();
  });

  Map<String, dynamic> song(String id) => {
    'ytid': id,
    'title': 'Song $id',
    'artist': 'Artist',
  };

  test('tracks a download from start to finish and keeps it', () {
    final entry = manager.started(song('a'));
    expect(manager.active.single.ytid, 'a');

    manager
      ..finished(entry)
      ..flush();

    expect(manager.active, isEmpty);
    expect(entry.status, DownloadStatus.done);
    final stored = Hive.box('userNoBackup').get('downloadHistory') as List;
    expect((stored.single as Map)['status'], 'done');
  });

  test('a retry replaces the earlier entry for the same song', () {
    manager.failed(manager.started(song('b')), const SocketException('x'));
    manager.started(song('b'));

    expect(manager.entries.value.where((e) => e.ytid == 'b'), hasLength(1));
    expect(manager.entries.value.first.status, DownloadStatus.downloading);
  });

  test('failures are told apart', () {
    expect(DownloadManager.failureFor(null), DownloadFailure.unavailable);
    expect(
      DownloadManager.failureFor(const SocketException('offline')),
      DownloadFailure.network,
    );
    expect(
      DownloadManager.failureFor(http.ClientException('reset')),
      DownloadFailure.network,
    );
    expect(
      DownloadManager.failureFor(StateError('bad')),
      DownloadFailure.other,
    );
    // YouTube refusing this device is not a song that is gone.
    expect(
      DownloadManager.failureFor(
        VideoUnplayableException("Sign in to confirm you're not a bot"),
      ),
      DownloadFailure.network,
    );
    // The age gate asks to sign in too, but it is closed to everyone.
    expect(
      DownloadManager.failureFor(
        VideoUnplayableException('Sign in to confirm your age'),
      ),
      DownloadFailure.unavailable,
    );
    expect(
      DownloadManager.failureFor(VideoUnavailableException('gone')),
      DownloadFailure.unavailable,
    );
  });

  test('history round-trips through storage', () {
    final entry = manager.started(song('c'));
    manager
      ..failed(entry, null)
      ..flush();

    final restored = DownloadEntry.fromMap(
      (Hive.box('userNoBackup').get('downloadHistory') as List).first as Map,
    );
    expect(restored.ytid, 'c');
    expect(restored.status, DownloadStatus.failed);
    expect(restored.failure, DownloadFailure.unavailable);
  });

  test('history keeps only the latest finished downloads', () {
    for (var i = 0; i < 250; i++) {
      manager.finished(manager.started(song('h$i')));
    }
    manager.flush();

    final history = manager.entries.value.where(
      (e) => e.status != DownloadStatus.downloading,
    );
    expect(history, hasLength(200));
    expect(history.first.ytid, 'h249');
    expect(
      Hive.box('userNoBackup').get('downloadHistory') as List,
      hasLength(200),
    );
  });

  test('clearing history keeps downloads in progress', () {
    manager
      ..finished(manager.started(song('d')))
      ..started(song('e'))
      ..clearHistory();

    final entries = manager.entries.value;
    expect(entries.map((e) => e.ytid), contains('e'));
    expect(entries.map((e) => e.ytid), isNot(contains('d')));
    expect(
      entries.every((e) => e.status == DownloadStatus.downloading),
      isTrue,
    );
  });

  group('the queue', () {
    // A saver that waits until the test lets it finish.
    final gates = <String, Completer<void>>{};
    var running = 0, peak = 0;
    final saved = <String>[];

    Future<void> save(
      Map<String, dynamic> song,
      void Function(double) onProgress,
    ) async {
      final id = song['ytid'] as String;
      running++;
      peak = running > peak ? running : peak;
      try {
        await (gates[id] ??= Completer<void>()).future;
        if (id.startsWith('stall')) throw TimeoutException('stalled');
        onProgress(0.5);
        if (id.startsWith('bad')) throw StateError('no');
        if (id.startsWith('gone')) throw VideoUnavailableException('gone');
        saved.add(id);
      } finally {
        running--;
      }
    }

    setUp(() {
      gates.clear();
      saved.clear();
      running = 0;
      peak = 0;
    });

    void open(String id) => (gates[id] ??= Completer<void>()).complete();

    test('runs a few at a time however many are asked for', () async {
      final all = [
        for (var i = 0; i < 8; i++) manager.download(song('q$i'), save),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(running, DownloadManager.maxConcurrent);
      expect(
        manager.entries.value.where((e) => e.status == DownloadStatus.queued),
        hasLength(8 - DownloadManager.maxConcurrent),
      );
      for (var i = 0; i < 8; i++) {
        open('q$i');
        await Future<void>.delayed(Duration.zero);
      }
      expect(await Future.wait(all), everyElement(isTrue));
      expect(peak, DownloadManager.maxConcurrent);
      expect(manager.active.where((e) => e.ytid.startsWith('q')), isEmpty);
    });

    test('asking twice for one song downloads it once', () async {
      final first = manager.download(song('s'), save);
      final second = manager.download(song('s'), save);
      expect(identical(first, second), isTrue);
      open('s');
      expect(await first, isTrue);
      expect(saved, ['s']);
      expect(manager.entries.value.where((e) => e.ytid == 's'), hasLength(1));
    });

    test('cancelling a song stops it while it runs', () async {
      final result = manager.download(song('c'), save);
      final other = manager.download(song('d'), save);
      await Future<void>.delayed(Duration.zero);
      expect(manager.cancel('c'), isTrue);
      open('c');
      open('d');
      expect(await result, isFalse);
      expect(await other, isTrue);
      expect(saved, ['d']);
      expect(manager.activeFor('c'), isNull);
      expect(manager.entries.value.where((e) => e.ytid == 'c'), isEmpty);
    });

    test(
      'a cancelled song waiting in the queue leaves the list at once',
      () async {
        final running = [
          for (var i = 0; i < DownloadManager.maxConcurrent; i++)
            manager.download(song('r$i'), save),
        ];
        final waiting = manager.download(song('w'), save);
        await Future<void>.delayed(Duration.zero);
        expect(manager.activeFor('w')?.status, DownloadStatus.queued);

        expect(manager.cancel('w'), isTrue);
        expect(manager.activeFor('w'), isNull);
        // It held no file, so it can be asked for again at once.
        final again = manager.download(song('w'), save);
        expect(manager.activeFor('w')?.status, DownloadStatus.queued);

        for (var i = 0; i < DownloadManager.maxConcurrent; i++) {
          open('r$i');
        }
        open('w');
        expect(await Future.wait(running), everyElement(isTrue));
        expect(await waiting, isFalse);
        expect(await again, isTrue);
        expect(saved.where((id) => id == 'w'), hasLength(1));
        expect(manager.entries.value.where((e) => e.ytid == 'w'), hasLength(1));
      },
    );

    test('a cancelled song that then errors is stopped, not failed', () async {
      final result = manager.download(song('stall'), save);
      await Future<void>.delayed(Duration.zero);
      expect(manager.cancel('stall'), isTrue);
      open('stall');
      expect(await result, isFalse);
      expect(manager.entries.value.where((e) => e.ytid == 'stall'), isEmpty);
    });

    test('stopping lets go of what runs and what waits', () async {
      final all = [
        for (var i = 0; i < 5; i++) manager.download(song('t$i'), save),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(running, DownloadManager.maxConcurrent);
      final stopped = manager.stopAll();
      // Those running notice at their next report; those waiting never start.
      for (var i = 0; i < 5; i++) {
        open('t$i');
      }
      await stopped;
      expect(await Future.wait(all), everyElement(isFalse));
      expect(
        manager.entries.value.where((e) => e.ytid.startsWith('t')),
        isEmpty,
      );
      expect(running, 0);
    });

    test(
      'a song asked for after a stop does not join the stopped one',
      () async {
        final stopping = manager.download(song('r'), save);
        await Future<void>.delayed(Duration.zero);
        final stopped = manager.stopAll();
        final again = manager.download(song('r'), save);
        expect(identical(stopping, again), isFalse);

        open('r');
        await stopped;
        expect(await stopping, isFalse);
        expect(await again, isTrue);
        expect(saved, ['r']);
      },
    );

    test('a download stopped while saving keeps the earlier failure', () async {
      manager.failed(manager.started(song('e')), StateError('x'));
      final retry = manager.download(song('e'), save);
      await Future<void>.delayed(Duration.zero);
      final stopped = manager.stopAll();
      open('e');
      await stopped;

      expect(await retry, isFalse);
      final entry = manager.entries.value.singleWhere((e) => e.ytid == 'e');
      expect(entry.status, DownloadStatus.failed);
    });

    test('a download is not started in offline mode', () async {
      offlineMode.value = true;
      addTearDown(() => offlineMode.value = false);
      expect(await manager.download(song('o'), save), isFalse);
      expect(manager.entries.value, isEmpty);
      expect(saved, isEmpty);
    });

    test('a cancelled song leaves the queue without being saved', () async {
      var cancelled = false;
      final blockers = [
        for (var i = 0; i < DownloadManager.maxConcurrent; i++)
          manager.download(song('b$i'), save),
      ];
      final waiting = manager.download(
        song('late'),
        save,
        cancelled: () => cancelled,
      );
      cancelled = true;
      for (var i = 0; i < DownloadManager.maxConcurrent; i++) {
        open('b$i');
      }
      await Future.wait(blockers);
      expect(await waiting, isFalse);
      expect(saved, isNot(contains('late')));
      expect(manager.entries.value.map((e) => e.ytid), isNot(contains('late')));
    });

    test(
      'a shared download is cancelled only when everyone cancelled',
      () async {
        final blockers = [
          for (var i = 0; i < DownloadManager.maxConcurrent; i++)
            manager.download(song('c$i'), save),
        ];
        // Two playlists want the same song; the first one is cancelled.
        final first = manager.download(
          song('shared'),
          save,
          cancelled: () => true,
        );
        final second = manager.download(
          song('shared'),
          save,
          cancelled: () => false,
        );
        expect(identical(first, second), isTrue);
        for (var i = 0; i < DownloadManager.maxConcurrent; i++) {
          open('c$i');
        }
        await Future.wait(blockers);
        open('shared');
        expect(await first, isTrue);
        expect(saved, contains('shared'));
      },
    );

    test('a song everyone cancelled is not downloaded', () async {
      final blockers = [
        for (var i = 0; i < DownloadManager.maxConcurrent; i++)
          manager.download(song('d$i'), save),
      ];
      final first = manager.download(
        song('dropped'),
        save,
        cancelled: () => true,
      );
      unawaited(manager.download(song('dropped'), save, cancelled: () => true));
      for (var i = 0; i < DownloadManager.maxConcurrent; i++) {
        open('d$i');
      }
      await Future.wait(blockers);
      expect(await first, isFalse);
      expect(saved, isNot(contains('dropped')));
    });

    test('the place is kept until the save has ended', () async {
      final slow = manager.download(song('slow'), save);
      await Future<void>.delayed(Duration.zero);
      expect(running, 1);
      // Nothing lets go of a save that is still writing.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(manager.active.map((e) => e.ytid), contains('slow'));
      expect(manager.download(song('slow'), save), same(slow));
      open('slow');
      expect(await slow, isTrue);
      expect(running, 0);
    });

    group('the end of a run', () {
      final notices = <DownloadBatch>[];
      void listen() => notices.add(manager.batch.value!);
      setUp(() {
        notices.clear();
        manager.batch.addListener(listen);
      });
      tearDown(() => manager.batch.removeListener(listen));

      Future<void> settle(
        List<Future<bool>> downloads,
        List<String> ids,
      ) async {
        ids.forEach(open);
        await Future.wait(downloads);
      }

      test(
        'waits a margin, then tells every playlist\'s failures once',
        () async {
          // Two playlists at once, each with songs that fail.
          final downloads = [
            manager.download(song('fine1'), save),
            manager.download(song('bad-a'), save),
            manager.download(song('gone-a'), save),
            manager.download(song('fine2'), save),
            manager.download(song('gone-b'), save),
          ];
          expect(manager.idle.value, isFalse);
          await settle(downloads, [
            'fine1',
            'bad-a',
            'gone-a',
            'fine2',
            'gone-b',
          ]);
          // Over, but not yet said: another playlist may start right now.
          expect(manager.idle.value, isFalse);
          expect(notices, isEmpty);

          await Future<void>.delayed(const Duration(milliseconds: 60));
          expect(manager.idle.value, isTrue);
          expect(notices, hasLength(1));
          expect(notices.single.failed, 3);
          expect(notices.single.unavailable, 2);
        },
      );

      test('a download inside the margin belongs to the same run', () async {
        await settle([manager.download(song('bad-1'), save)], ['bad-1']);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await settle([manager.download(song('bad-2'), save)], ['bad-2']);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(notices.single.failed, 2);
      });

      test('an open run holds the end, however long the gap', () async {
        final run = manager.openRun();
        await settle([manager.download(song('bad-r1'), save)], ['bad-r1']);
        // Longer than the margin, with nothing queued: the next playlist is
        // still loading.
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(manager.idle.value, isFalse);
        expect(notices, isEmpty);

        await settle([manager.download(song('gone-r2'), save)], ['gone-r2']);
        run.close();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(manager.idle.value, isTrue);
        expect(notices, hasLength(1));
        expect(notices.single.failed, 2);
        expect(notices.single.unavailable, 1);
      });

      test(
        'the end waits for every open run, and closing twice counts once',
        () async {
          final first = manager.openRun();
          final second = manager.openRun();
          first
            ..close()
            ..close();
          await Future<void>.delayed(const Duration(milliseconds: 60));
          expect(manager.idle.value, isFalse);
          second.close();
          await Future<void>.delayed(const Duration(milliseconds: 60));
          expect(manager.idle.value, isTrue);
          // Nothing was downloaded: nothing to tell.
          expect(notices, isEmpty);
        },
      );

      test('a song that failed and then worked is not told', () async {
        final run = manager.openRun();
        manager
          ..failed(manager.started(song('retried')), StateError('x'))
          ..failed(manager.started(song('stays')), StateError('x'))
          ..finished(manager.started(song('retried')));
        run.close();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(notices.single.failed, 1);
      });

      test('a run without failures says nothing', () async {
        await settle([manager.download(song('ok'), save)], ['ok']);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(manager.idle.value, isTrue);
        expect(notices, isEmpty);
      });

      test('the next run starts counting from zero', () async {
        await settle([manager.download(song('bad-x'), save)], ['bad-x']);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        await settle([manager.download(song('gone-y'), save)], ['gone-y']);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(notices.map((n) => n.failed), [1, 1]);
        expect(notices.map((n) => n.unavailable), [0, 1]);
        expect(notices.first.id, isNot(notices.last.id));
      });
    });

    group('the count of a batch', () {
      BatchProgress now() => manager.progress.value;

      test('counts what was asked for, saved and failed', () async {
        final all = [
          manager.download(song('fine1'), save),
          manager.download(song('bad-a'), save),
          manager.download(song('gone-a'), save),
          manager.download(song('fine2'), save),
        ];
        expect(now(), (done: 0, total: 4, failed: 0));

        open('fine1');
        await Future<void>.delayed(Duration.zero);
        expect(now(), (done: 1, total: 4, failed: 0));

        open('bad-a');
        await Future<void>.delayed(Duration.zero);
        expect(now(), (done: 1, total: 4, failed: 1));

        open('gone-a');
        open('fine2');
        await Future.wait(all);
        expect(now(), (done: 2, total: 4, failed: 2));
      });

      test('starts again from zero once everything is idle', () async {
        await (() async {
          final download = manager.download(song('bad-z'), save);
          open('bad-z');
          await download;
        })();
        expect(now(), (done: 0, total: 1, failed: 1));

        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(manager.idle.value, isTrue);
        expect(now(), (done: 0, total: 0, failed: 0));

        final next = manager.download(song('fine-z'), save);
        expect(now(), (done: 0, total: 1, failed: 0));
        open('fine-z');
        await next;
        expect(now(), (done: 1, total: 1, failed: 0));
      });

      test('a download inside the margin joins the same count', () async {
        final first = manager.download(song('m1'), save);
        open('m1');
        await first;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final second = manager.download(song('m2'), save);
        open('m2');
        await second;
        expect(now(), (done: 2, total: 2, failed: 0));
      });

      test('a song that failed and then worked counts once, as saved', () {
        manager.failed(manager.started(song('r')), StateError('x'));
        expect(now(), (done: 0, total: 1, failed: 1));
        manager.finished(manager.started(song('r')));
        expect(now(), (done: 1, total: 1, failed: 0));
      });

      test('a song asked for twice counts once', () async {
        final first = manager.download(song('twice'), save);
        unawaited(manager.download(song('twice'), save));
        expect(now().total, 1);
        open('twice');
        await first;
        expect(now(), (done: 1, total: 1, failed: 0));
      });

      test('a cancelled or stopped song does not count', () async {
        final blockers = [
          for (var i = 0; i < DownloadManager.maxConcurrent; i++)
            manager.download(song('n$i'), save),
        ];
        final dropped = manager.download(
          song('left'),
          save,
          cancelled: () => true,
        );
        expect(now().total, DownloadManager.maxConcurrent + 1);
        for (var i = 0; i < DownloadManager.maxConcurrent; i++) {
          open('n$i');
        }
        await Future.wait(blockers);
        expect(await dropped, isFalse);
        expect(now(), (
          done: DownloadManager.maxConcurrent,
          total: DownloadManager.maxConcurrent,
          failed: 0,
        ));

        await Future<void>.delayed(const Duration(milliseconds: 60));
        final stopping = manager.download(song('stopped'), save);
        final stopped = manager.stopAll();
        open('stopped');
        await stopped;
        expect(await stopping, isFalse);
        expect(now().total, 0);
      });

      test(
        'a failed retry that is cancelled stays counted as failed',
        () async {
          manager.failed(manager.started(song('again')), StateError('x'));
          final blockers = [
            for (var i = 0; i < DownloadManager.maxConcurrent; i++)
              manager.download(song('p$i'), save),
          ];
          final retry = manager.download(
            song('again'),
            save,
            cancelled: () => true,
          );
          for (var i = 0; i < DownloadManager.maxConcurrent; i++) {
            open('p$i');
          }
          await Future.wait(blockers);
          expect(await retry, isFalse);
          expect(now().failed, 1);
          expect(now().total, DownloadManager.maxConcurrent + 1);
        },
      );
    });

    test('cancelling a new try keeps the earlier entry of the song', () async {
      manager.failed(manager.started(song('again')), StateError('x'));
      final blockers = [
        for (var i = 0; i < DownloadManager.maxConcurrent; i++)
          manager.download(song('k$i'), save),
      ];
      final retry = manager.download(
        song('again'),
        save,
        cancelled: () => true,
      );
      for (var i = 0; i < DownloadManager.maxConcurrent; i++) {
        open('k$i');
      }
      await Future.wait(blockers);
      expect(await retry, isFalse);
      final entry = manager.entries.value.firstWhere((e) => e.ytid == 'again');
      expect(entry.status, DownloadStatus.failed);
    });

    test('a failure frees its place and says why', () async {
      final bad = manager.download(song('bad1'), save);
      final gone = manager.download(song('gone1'), save);
      final fine = manager.download(song('fine'), save);
      open('bad1');
      open('gone1');
      open('fine');
      expect(await Future.wait([bad, gone, fine]), [false, false, true]);
      DownloadFailure? failureOf(String id) =>
          manager.entries.value.firstWhere((e) => e.ytid == id).failure;
      expect(failureOf('bad1'), DownloadFailure.other);
      expect(failureOf('gone1'), DownloadFailure.unavailable);
      expect(running, 0);
    });
  });
}
