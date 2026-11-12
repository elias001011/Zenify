import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/listening_stats_utils.dart';

void main() {
  late Directory dir;
  late DateTime now;
  late ListeningStatsService stats;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zenify_stats_full_month');
    Hive.init(dir.path);
    await Hive.openBox('settings');
    await Hive.openBox('user');
    await Hive.openBox('userNoBackup');
    wrappedEnabled.value = true;
    now = DateTime(2026, 11, 3, 12);
    stats = ListeningStatsService(now: () => now);
  });
  tearDown(() async {
    await stats.flush();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  /// A month the device has stored with [count] songs, each heard to the end
  /// once: the least of them has far more seconds than a song that has just
  /// qualified.
  Future<void> seed(int count) async {
    final stored = createEmptyListeningStats(2026, currentMonthKey: '2026-11');
    stored['currentMonth'] = {
      'totalSeconds': count * 300,
      'songs': {
        for (var i = 0; i < count; i++)
          'old$i': {
            'ytid': 'old$i',
            'title': 'Old $i',
            'seconds': 200 + i,
            'playCount': 1,
            'listeningCount': 1,
            'lastPlayed': now.toIso8601String(),
          },
      },
    };
    await Hive.box('user').put(ListeningStatsService.storageKey, stored);
    stats.reload();
  }

  Map<String, dynamic> songs() =>
      stats.monthStats('2026-11')!['songs'] as Map<String, dynamic>;

  Map storedSongs() =>
      (Hive.box('user').get(ListeningStatsService.storageKey)['currentMonth']
              as Map)['songs']
          as Map;

  void listen(Map<String, dynamic> song, int seconds) {
    stats.startListeningSession(song);
    now = now.add(Duration(seconds: seconds));
    stats.finishListeningSession(countCurrentTick: true, wasPlaying: true);
  }

  test('a song new to a month of many songs counts, with all of it', () async {
    await seed(wrappedCurrentMonthSongsLimit + 50);

    listen({'ytid': 'new', 'title': 'New'}, 100);
    listen({'ytid': 'other', 'title': 'Other'}, 90);

    // Nothing was cut to make room: both are there, with what was heard.
    expect(songs(), hasLength(wrappedCurrentMonthSongsLimit + 52));
    expect(songs()['new'], containsPair('playCount', 1));
    expect(songs()['new'], containsPair('seconds', 100));
    expect(songs()['other'], containsPair('seconds', 90));
  });

  test(
    'only the best songs are backed up, the others stay on the device',
    () async {
      await seed(wrappedCurrentMonthSongsLimit + 50);
      listen({'ytid': 'new', 'title': 'New'}, 100);
      await stats.flush();

      // What a backup or a sync takes is the size it always was.
      expect(storedSongs(), hasLength(wrappedCurrentMonthSongsLimit));
      expect(storedSongs(), contains('old299'));
      expect(storedSongs(), isNot(contains('new')));

      // And the device gives the rest back after a restart.
      stats.reload();
      expect(songs(), hasLength(wrappedCurrentMonthSongsLimit + 51));
      expect(songs()['new'], containsPair('seconds', 100));
    },
  );

  test('a song that rose into the best ones is not kept twice', () async {
    await seed(wrappedCurrentMonthSongsLimit + 5);
    songs();
    await stats.flush();

    // Heard for a long time, a song of the device alone becomes one of the best.
    listen({'ytid': 'old0', 'title': 'Old 0'}, 4000);
    await stats.flush();
    expect(storedSongs(), contains('old0'));

    stats.reload();
    expect(songs()['old0'], containsPair('seconds', 4200));
    expect(songs(), hasLength(wrappedCurrentMonthSongsLimit + 5));
  });

  test('a new month starts without the extra songs of the last', () async {
    await seed(wrappedCurrentMonthSongsLimit + 50);
    songs();
    await stats.flush();
    expect(Hive.box('userNoBackup').get('wrappedMonthExtra'), isNotNull);

    now = DateTime(2026, 12, 1, 9);
    stats.reload();
    expect(stats.monthStats('2026-12')?['songs'] ?? const {}, isEmpty);
    listen({'ytid': 'new', 'title': 'New'}, 100);
    await stats.flush();

    expect(Hive.box('userNoBackup').get('wrappedMonthExtra'), isNull);
  });

  test('a restored backup does not take what the device kept', () async {
    await seed(wrappedCurrentMonthSongsLimit + 50);
    songs();
    await stats.flush();

    // A full month from another device, as a restore or a sync writes it.
    final restored = createEmptyListeningStats(
      2026,
      currentMonthKey: '2026-11',
    );
    restored['currentMonth'] = {
      'totalSeconds': 99000,
      'songs': {
        for (var i = 0; i < wrappedCurrentMonthSongsLimit; i++)
          'other$i': {
            'ytid': 'other$i',
            'title': 'Other $i',
            'seconds': 300,
            'playCount': 1,
            'listeningCount': 1,
            'lastPlayed': now.toIso8601String(),
          },
      },
    };
    await Hive.box('user').put(ListeningStatsService.storageKey, restored);
    stats.reload();

    expect(songs(), hasLength(wrappedCurrentMonthSongsLimit));
    expect(songs().keys, everyElement(startsWith('other')));
  });

  test('songs kept by an older version still come back', () async {
    await seed(wrappedCurrentMonthSongsLimit + 50);
    songs();
    await stats.flush();
    final extra = Map.of(Hive.box('userNoBackup').get('wrappedMonthExtra'))
      ..remove('totalSeconds');
    await Hive.box('userNoBackup').put('wrappedMonthExtra', extra);

    stats.reload();

    expect(songs(), hasLength(wrappedCurrentMonthSongsLimit + 50));
  });

  test('clearing the recap clears what the device kept too', () async {
    await seed(wrappedCurrentMonthSongsLimit + 50);
    songs();
    await stats.flush();
    expect(Hive.box('userNoBackup').get('wrappedMonthExtra'), isNotNull);

    await stats.clearStats();

    expect(Hive.box('userNoBackup').get('wrappedMonthExtra'), isNull);
    stats.reload();
    expect(stats.monthStats('2026-11')?['songs'] ?? const {}, isEmpty);
  });

  test(
    'past the limit of the device the song being played still stays',
    () async {
      await seed(wrappedWorkingSongsLimit);

      listen({'ytid': 'new', 'title': 'New'}, 100);

      expect(songs(), hasLength(wrappedWorkingSongsLimit));
      expect(songs()['new'], containsPair('seconds', 100));
      expect(songs(), isNot(contains('old0')));
    },
  );
}
