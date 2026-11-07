import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/settings_manager.dart';

import 'support/app_harness.dart';

void main() {
  // The binding blocks real HTTP requests, so only the check below is heard.
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppSettings();

  test(
    'a cached URL that never answers is dropped instead of waited on',
    () async {
      const songId = 'cachedUrlSong';
      final key = 'song_${songId}_${audioQualitySetting.value}_url';
      final cache = Hive.box('cache');
      await cache.put(key, 'https://example.com/stream');
      // Older than the hour after which the URL is asked about again.
      await cache.put(
        '${key}_date',
        DateTime.now().subtract(const Duration(hours: 2)),
      );

      var asked = 0;
      await http.runWithClient(
        () async {
          await fetchSongStreamUrl(songId, false);
        },
        () => MockClient((_) {
          asked++;
          return Completer<http.Response>().future;
        }),
      );

      expect(asked, 1);
      expect(cache.containsKey(key), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
