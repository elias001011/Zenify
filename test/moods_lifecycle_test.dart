import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/moods/mix_engine.dart';
import 'package:musify/services/moods/moods_preferences.dart';
import 'package:musify/services/moods/moods_service.dart';
import 'package:musify/services/moods/moods_worker.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/settings_manager.dart';

List<Map> _songs(String prefix) => [
  for (var i = 0; i < 10; i++)
    {'ytid': '$prefix$i', 'title': '$prefix $i', 'artist': 'Artist $i'},
];

class _FixtureMoods extends MoodsService {
  int made = 0;
  Completer<List<Map>>? pending;

  @override
  Future<List<Map>> mix({
    Discovery? discovery,
    int length = 40,
    Random? random,
  }) async {
    made++;
    return pending == null ? _songs('generation$made') : pending!.future;
  }
}

// A top-level factory ensures the worker gets only the ports it needs.
Future<String> Function() _slowReading(SendPort started, SendPort finished) =>
    () async {
      started.send(true);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      finished.send(true);
      return 'finished';
    };

Future<int> _answer() async => 42;

void main() {
  late Directory directory;
  late _FixtureMoods service;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('zenify_moods_lifecycle');
    Hive.init(directory.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box);
    }
  });
  setUp(() async {
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.box(box).clear();
    }
    offlineMode.value = false;
    moodsEnabled.value = true;
    moodsTuning.value = const MoodsTuning();
    languageSetting = const Locale('en');
    userCustomPlaylists.value = [];
    userPlaylistFolders.value = [];
    userOfflineSongs.value = [];
    userLikedSongsList.value = [];
    userRecentlyPlayed.value = [];
    listeningStatsService.reload();
    service = _FixtureMoods();
  });
  tearDown(() => service.dispose());
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'current playlists regenerate immediately after changing the tuning',
    () async {
      final first = await service.playlist('zenify:daily');
      expect(first!['list'], _songs('generation1'));
      await service.playlist('zenify:daily');
      expect(service.made, 1);

      await setMoodsTuning(const MoodsTuning(discovery: Discovery.adventurous));
      final refreshed = await service.playlist('zenify:daily');
      expect(refreshed!['list'], _songs('generation2'));
      expect(service.made, 2);
    },
  );

  test('a tuning change mid-generation remakes the playlist instead of dropping it', () async {
    service.pending = Completer<List<Map>>();
    final pending = service.playlist('zenify:daily');
    await setMoodsTuning(const MoodsTuning(discovery: Discovery.familiar));
    service.pending!.complete(_songs('late'));
    expect((await pending)!['list'], _songs('late'));
    expect(service.made, 2);
  });

  test('a tuning reloaded unchanged from storage notifies nobody', () async {
    await setMoodsTuning(
      const MoodsTuning(
        excludedGenres: {'Jazz', 'Rock'},
        blockedArtists: {'x'},
      ),
    );
    reloadMoodsFromStorage();
    var notified = 0;
    void count() => notified++;
    moodsTuning.addListener(count);
    savedZenifyPlaylists.addListener(count);
    addTearDown(() {
      moodsTuning.removeListener(count);
      savedZenifyPlaylists.removeListener(count);
    });
    reloadMoodsFromStorage();
    expect(notified, 0);
    expect(
      const MoodsTuning(
        excludedGenres: {'Rock', 'Jazz'},
        blockedArtists: {'x'},
      ),
      moodsTuning.value,
    );
  });

  test('blocked artists are removed even from an offline fallback', () async {
    await service.playlist('zenify:daily');
    await setMoodsTuning(const MoodsTuning(blockedArtists: {'artist0'}));
    offlineMode.value = true;
    final fallback = await service.playlist('zenify:daily');
    expect((fallback!['list'] as List).length, 9);
    expect(
      (fallback['list'] as List).any((song) => song['artist'] == 'Artist 0'),
      isFalse,
    );
    expect(service.made, 1);
  });

  test('a damaged cached expiry never breaks the playlist page', () async {
    await Hive.box('cache').put('moods:playlist:zenify:daily', {
      'ytid': 'zenify:daily',
      'language': 'en',
      'until': 'not a date',
      'list': _songs('old'),
    });
    final fresh = await service.playlist('zenify:daily');
    expect(fresh!['list'], _songs('generation1'));
  });

  test(
    'clearing the cache prevents a pending generation from writing back',
    () async {
      service.pending = Completer<List<Map>>();
      final pending = service.playlist('zenify:daily');
      expect(service.made, 1);
      await service.clearCache();
      service.pending!.complete(_songs('late'));
      expect(await pending, isNull);
      expect(Hive.box('cache').keys, isEmpty);
    },
  );

  test(
    'offline entry points never start a mix, mood, radio or catalog read',
    () async {
      final real = MoodsService();
      addTearDown(real.dispose);
      offlineMode.value = true;
      expect(await real.mix(), isEmpty);
      expect(await real.mood(Mood.chill), isEmpty);
      expect(await real.play(Mood.mix), isFalse);
      expect(await real.playRadio(_songs('seed'), title: 'Radio'), isFalse);
      expect(await real.radio('dQw4w9WgXcQ'), isEmpty);
      expect(await real.detectedGenres(), isEmpty);
      expect(await real.playlists().toList(), isEmpty);
      expect(await real.playlist('zenify:daily'), isNull);
    },
  );

  test('playlists kept in folders contribute to the taste', () {
    userPlaylistFolders.value = [
      {
        'id': 'folder',
        'playlists': [
          {'ytid': 'customId-inside', 'list': _songs('kept')},
        ],
      },
    ];
    expect(service.taste().known, contains('kept0'));
  });

  test('library edits invalidate the short taste memo', () {
    expect(service.taste().known, isEmpty);
    userLikedSongsList.value = _songs('liked');
    expect(service.taste().known, contains('liked0'));
  });

  test(
    'clearing the cache also forgets learned non-song classifications',
    () async {
      await Hive.box('cache').put('moods:notSongs', ['liked0']);
      userLikedSongsList.value = _songs('liked');
      expect(
        service.taste().seeds.map((s) => s.song['ytid']),
        isNot(contains('liked0')),
      );
      await service.clearCache();
      expect(
        service.taste().seeds.map((s) => s.song['ytid']),
        contains('liked0'),
      );
    },
  );

  test(
    'workers stop their operation on cancellation and can be reused',
    () async {
      final worker = MoodsWorker();
      final started = ReceivePort(), finished = ReceivePort();
      addTearDown(started.close);
      addTearDown(finished.close);
      addTearDown(worker.cancel);
      final lateMessages = <dynamic>[];
      finished.listen(lateMessages.add);
      final result = worker.run(
        _slowReading(started.sendPort, finished.sendPort),
      );
      final cancelled = expectLater(result, throwsA(isA<MoodsCancelled>()));
      await started.first;
      worker.cancel();
      await cancelled;
      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(lateMessages, isEmpty);
      expect(await worker.run(_answer), 42);
    },
  );

  test(
    'a worker cancelled before spawning never starts its operation',
    () async {
      final worker = MoodsWorker();
      final started = ReceivePort(), finished = ReceivePort();
      addTearDown(started.close);
      addTearDown(finished.close);
      final starts = <dynamic>[];
      started.listen(starts.add);
      final result = worker.run(
        _slowReading(started.sendPort, finished.sendPort),
      );
      final cancelled = expectLater(result, throwsA(isA<MoodsCancelled>()));
      worker.cancel();
      await cancelled;
      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(starts, isEmpty);
    },
  );
}
