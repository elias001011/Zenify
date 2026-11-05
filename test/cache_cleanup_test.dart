import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/data_manager.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings();

  test(
    'the cache keeps what is recent and the Moods, and drops the rest',
    () async {
      final cache = Hive.box('cache');
      DateTime daysAgo(int days) =>
          DateTime.now().subtract(Duration(days: days));

      await addOrUpdateData<String>('cache', 'song_recent_1_url', 'recent');
      await addOrUpdateData<List>('cache', 'playlistSongs29', [1]);
      await cache.put('playlistSongs29_date', daysAgo(29));
      await addOrUpdateData<String>('cache', 'song_old_1_url', 'old');
      await cache.put('song_old_1_url_date', daysAgo(31));
      // Left without a date by whatever wrote it.
      await cache.put('undated', 'x');
      // The Moods date their own entries and keep them past any age.
      await cache.put('moods:pool:chill', {
        'at': daysAgo(60).toIso8601String(),
      });
      await cache.put('moods:notSongs', ['abc']);

      await cleanupOldCacheEntries();

      expect(cache.keys, {
        'song_recent_1_url',
        'song_recent_1_url_date',
        'playlistSongs29',
        'playlistSongs29_date',
        'moods:pool:chill',
        'moods:notSongs',
      });
      expect(await getData('cache', 'song_old_1_url'), isNull);
      expect(await getData('cache', 'song_recent_1_url'), 'recent');
    },
  );
}
