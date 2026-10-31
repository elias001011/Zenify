import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:musify/services/download_manager.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  late Directory dir;
  final manager = DownloadManager.instance;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('musify_downloads');
    Hive.init(dir.path);
    await Hive.openBox('userNoBackup');
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  setUp(manager.clearHistory);

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
      void Function(double) _,
    ) async {
      final id = song['ytid'] as String;
      running++;
      peak = running > peak ? running : peak;
      try {
        await (gates[id] ??= Completer<void>()).future;
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
