import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/download_manager.dart';
import 'package:musify/services/downloads_location_service.dart';
import 'package:musify/services/io_service.dart';
import 'package:musify/services/playlist_download_service.dart';

void main() {
  late Directory tempDir;
  late String defaultRoot;
  late String customRoot;

  const songId = 'dQw4w9WgXcQ';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('musify_downloads_test');
    Hive.init('${tempDir.path}/hive');
    await Hive.openBox('settings');
    await Hive.openBox('user');
    await Hive.openBox('userNoBackup');
    await Hive.openBox('cache');
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    defaultRoot = '${tempDir.path}/default';
    customRoot = '${tempDir.path}/custom';
    for (final root in [defaultRoot, customRoot]) {
      final directory = Directory(root);
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
    await Hive.box('userNoBackup').clear();

    applicationDirPath = defaultRoot;
    await DownloadsLocation.initialise();
    await FilePaths.ensureDirectoriesExist();

    await File(FilePaths.getAudioPath(songId)).writeAsString('audio');
    await File(FilePaths.getArtworkPath(songId)).writeAsString('artwork');
    // Not ours: must stay where it is.
    await File('$defaultRoot/tracks/my song.m4a').writeAsString('mine');

    final song = {
      'ytid': songId,
      'audioPath': FilePaths.getAudioPath(songId),
      'artworkPath': FilePaths.getArtworkPath(songId),
    };
    userOfflineSongs.value = [song];
    offlinePlaylistService.offlinePlaylists.value = [
      {
        'ytid': 'playlist',
        'list': [Map.of(song)],
      },
    ];
  });

  test('moves downloads and rewrites the stored paths', () async {
    final status = await DownloadsLocation.change(customRoot);

    expect(status, DownloadsMoveStatus.moved);
    expect(downloadsDirPath, customRoot);
    expect(DownloadsLocation.customPath, customRoot);

    final audio = '$customRoot/tracks/$songId.m4a';
    final artwork = '$customRoot/artworks/$songId.jpg';
    expect(File(audio).readAsStringSync(), 'audio');
    expect(File(artwork).readAsStringSync(), 'artwork');
    expect(File('$defaultRoot/tracks/$songId.m4a').existsSync(), isFalse);
    expect(File('$defaultRoot/tracks/my song.m4a').existsSync(), isTrue);

    expect(userOfflineSongs.value.single['audioPath'], audio);
    expect(userOfflineSongs.value.single['artworkPath'], artwork);
    final playlistSong =
        (offlinePlaylistService.offlinePlaylists.value.single as Map)['list']
            .single;
    expect(playlistSong['audioPath'], audio);
  });

  test('a collision preserves both files and the original path', () async {
    final source = File('$defaultRoot/tracks/$songId.m4a');
    final target = File('$customRoot/tracks/$songId.m4a');
    await target.parent.create(recursive: true);
    await target.writeAsString('other'); // Same length as 'audio'.
    final status = await DownloadsLocation.change(customRoot);
    expect(status, DownloadsMoveStatus.partiallyMoved);
    expect(source.readAsStringSync(), 'audio');
    expect(target.readAsStringSync(), 'other');
    expect(userOfflineSongs.value.single['audioPath'], source.path);
  });

  test('checking writability preserves a pre-existing probe file', () async {
    final probe = File('$customRoot/tracks/.musify-write-test');
    await probe.parent.create(recursive: true);
    await probe.writeAsString('keep');
    await DownloadsLocation.change(customRoot);
    expect(probe.readAsStringSync(), 'keep');
  });

  test('preserves unrelated partial files in the destination', () async {
    final partial = File('$customRoot/tracks/$songId.m4a.partial');
    await partial.parent.create(recursive: true);
    await partial.writeAsString('keep');
    await DownloadsLocation.change(customRoot);
    expect(partial.readAsStringSync(), 'keep');
  });

  test(
    'exclusive storage operations block new transfers and folder changes',
    () async {
      final manager = DownloadManager.instance;
      await manager.withExclusiveStorage(() async {
        expect(
          await DownloadsLocation.change(customRoot),
          DownloadsMoveStatus.busy,
        );
        expect(
          await manager.download({'ytid': songId}, (_, _) async {
            fail('The transfer must not start while storage is reserved');
          }),
          isFalse,
        );
      });
      expect(
        await DownloadsLocation.change(customRoot),
        DownloadsMoveStatus.moved,
      );
    },
  );

  test('reuses a verified copy left by an interrupted move', () async {
    final target = File('$customRoot/tracks/$songId.m4a');
    await target.parent.create(recursive: true);
    await target.writeAsString('audio');

    expect(
      await DownloadsLocation.change(customRoot),
      DownloadsMoveStatus.moved,
    );
    final saved = (Hive.box('userNoBackup').get('offlineSongs') as List).single;
    expect(saved['audioPath'], target.path);
    expect(target.readAsStringSync(), 'audio');
    expect(File('$defaultRoot/tracks/$songId.m4a').existsSync(), isFalse);
  });

  test(
    'checks old offline flags and retains temporarily missing files',
    () async {
      final complete =
          offlinePlaylistService.offlinePlaylists.value.single as Map;
      offlinePlaylistService.offlinePlaylists.value = [
        complete,
        {
          'ytid': 'partial',
          'list': [
            {'ytid': songId},
            {'ytid': 'missing'},
          ],
        },
      ];
      final audio = File(FilePaths.getAudioPath(songId));
      await audio.delete();
      await offlinePlaylistService.validateStoredPlaylists();

      expect(offlinePlaylistService.availableOfflinePlaylists, isEmpty);
      expect(offlinePlaylistService.offlinePlaylists.value, [complete]);
      expect(userOfflineSongs.value, hasLength(1));

      await audio.writeAsString('audio');
      await offlinePlaylistService.validateStoredPlaylists();
      expect(offlinePlaylistService.getOfflinePlaylist('playlist'), complete);
    },
  );

  test('moving back to the default forgets the custom folder', () async {
    await DownloadsLocation.change(customRoot);
    final status = await DownloadsLocation.change(null);

    expect(status, DownloadsMoveStatus.moved);
    expect(downloadsDirPath, defaultRoot);
    expect(DownloadsLocation.customPath, isNull);
    expect(
      userOfflineSongs.value.single['audioPath'],
      '$defaultRoot/tracks/$songId.m4a',
    );
    expect(Directory('$customRoot/tracks').existsSync(), isFalse);
  });

  test('a missing custom folder falls back to the default', () async {
    await DownloadsLocation.change(customRoot);
    Directory(customRoot).deleteSync(recursive: true);

    await DownloadsLocation.initialise();

    expect(DownloadsLocation.unavailable, isTrue);
    expect(downloadsDirPath, defaultRoot);
    expect(DownloadsLocation.customPath, customRoot);
    expect(Directory(customRoot).existsSync(), isFalse);
  });

  test('an unwritable folder changes nothing', () async {
    final blocker = File('${tempDir.path}/not-a-folder');
    await blocker.writeAsString('x');

    final status = await DownloadsLocation.change(blocker.path);

    expect(status, DownloadsMoveStatus.notWritable);
    expect(downloadsDirPath, defaultRoot);
    expect(File(FilePaths.getAudioPath(songId)).existsSync(), isTrue);
  });

  test('deleting all downloads leaves foreign files alone', () async {
    await FilePaths.deleteDownloadedFiles(userOfflineSongs.value);

    expect(File('$defaultRoot/tracks/$songId.m4a').existsSync(), isFalse);
    expect(File('$defaultRoot/artworks/$songId.jpg').existsSync(), isFalse);
    expect(File('$defaultRoot/tracks/my song.m4a').existsSync(), isTrue);
  });

  test('the same folder under another spelling keeps the only copy', () async {
    final alias = '${tempDir.path}/alias';
    Link(alias).createSync(defaultRoot);

    final status = await DownloadsLocation.change(alias);

    expect(status, DownloadsMoveStatus.moved);
    expect(File(FilePaths.getAudioPath(songId)).readAsStringSync(), 'audio');
    expect(File('$defaultRoot/artworks/$songId.jpg').existsSync(), isTrue);
    Link(alias).deleteSync();
  });

  test('copies files kept outside our folders and leaves them', () async {
    const legacyId = 'bbbbbbbbbbb';
    final legacy = Directory('${tempDir.path}/Documents/tracks')
      ..createSync(recursive: true);
    final legacyAudio = File('${legacy.path}/$legacyId.m4a')
      ..writeAsStringSync('legacy');
    userOfflineSongs.value = [
      ...userOfflineSongs.value,
      {'ytid': legacyId, 'audioPath': legacyAudio.path},
    ];

    final status = await DownloadsLocation.change(customRoot);

    final copied = '$customRoot/tracks/$legacyId.m4a';
    expect(status, DownloadsMoveStatus.moved);
    expect(File(copied).readAsStringSync(), 'legacy');
    expect(legacyAudio.existsSync(), isTrue);
    expect(userOfflineSongs.value.last['audioPath'], copied);
  });

  test(
    'copies a referenced download through a link without moving its target',
    () async {
      if (Platform.isWindows) return;
      final tracks = Directory('$defaultRoot/tracks');
      final external = await tracks.rename('$defaultRoot/external');
      final original = File('${external.path}/$songId.m4a');
      await Link(tracks.path).create(external.path);

      expect(
        await DownloadsLocation.change(customRoot),
        DownloadsMoveStatus.moved,
      );
      expect(original.readAsStringSync(), 'audio');
      expect(Link(tracks.path).existsSync(), isTrue);
      final stored = userOfflineSongs.value.single['audioPath'] as String;
      expect(stored, '$customRoot/tracks/$songId.m4a');
      expect(File(stored).readAsStringSync(), 'audio');
    },
  );

  test(
    'a linked destination subfolder leaves the original library alone',
    () async {
      if (Platform.isWindows) return;
      final external = await Directory('$defaultRoot/external').create();
      await Directory(customRoot).create();
      await Link('$customRoot/tracks').create(external.path);

      expect(
        await DownloadsLocation.change(customRoot),
        DownloadsMoveStatus.notWritable,
      );
      expect(await external.list().isEmpty, isTrue);
      expect(downloadsDirPath, defaultRoot);
      expect(File(FilePaths.getAudioPath(songId)).readAsStringSync(), 'audio');
    },
  );
}
