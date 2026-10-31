import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/download_manager.dart';
import 'package:musify/services/io_service.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('zenify_download_share');
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
    downloadsDirPath = directory.path;
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets('the same song asked twice is downloaded once, and again later', (
    tester,
  ) async {
    // The test binding refuses real requests, so downloads fail at once.
    await tester.runAsync(() async {
      final song = {'ytid': 'dQw4w9WgXcQ', 'title': 'Song', 'artist': 'Artist'};
      final first = makeSongOffline(song);
      final second = makeSongOffline(song);
      expect(identical(first, second), isTrue);
      // One row in the Downloads tab, not one per request.
      expect(
        DownloadManager.instance.entries.value.where(
          (entry) => entry.ytid == 'dQw4w9WgXcQ',
        ),
        hasLength(1),
      );
      await first.timeout(const Duration(seconds: 20), onTimeout: () => false);

      final later = makeSongOffline(song);
      expect(identical(first, later), isFalse);
      await later.timeout(const Duration(seconds: 20), onTimeout: () => false);
    });
  });
}
