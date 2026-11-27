import 'dart:async';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/download_manager.dart';
import 'package:musify/services/io_service.dart';
import 'package:musify/services/playlist_download_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/playlist_page/download_button.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings(inMemory: true);

  test(
    'removeSongFromOffline waits for an active exclusive storage operation',
    () async {
      final root = Directory.systemTemp.createTempSync('zenify_remove_wait');
      addTearDown(() => root.deleteSync(recursive: true));
      applicationDirPath = downloadsDirPath = root.path;
      Directory('${root.path}/${FilePaths.tracksDir}').createSync(
        recursive: true,
      );

      const id = 'aaaaaaaaaaa';
      final audio = File(FilePaths.getAudioPath(id))..writeAsStringSync('data');
      userOfflineSongs.value = [
        {'ytid': id, 'audioPath': audio.path},
      ];
      addTearDown(() => userOfflineSongs.value = []);

      final entered = Completer<void>();
      final release = Completer<void>();
      final holder = DownloadManager.instance.withExclusiveStorage(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;

      final removal = removeSongFromOffline(id);
      await Future<void>.delayed(Duration.zero);
      expect(audio.existsSync(), isTrue);

      release.complete();
      await holder;
      expect(await removal, isTrue);
      expect(audio.existsSync(), isFalse);
      expect(userOfflineSongs.value, isEmpty);
    },
  );

  testWidgets(
    'PlaylistDownloadButton offers download when a stored playlist has missing audio',
    (tester) async {
      final root = Directory.systemTemp.createTempSync('zenify_unavail_pl');
      addTearDown(() => root.deleteSync(recursive: true));
      offlineMode.value = false;
      addTearDown(() => offlineMode.value = false);
      applicationDirPath = downloadsDirPath = root.path;
      Directory('${root.path}/${FilePaths.tracksDir}').createSync(
        recursive: true,
      );

      const songId = 'bbbbbbbbbbb';
      const playlistId = 'PL_missing_audio';
      final audio = File(FilePaths.getAudioPath(songId));
      final song = {'ytid': songId, 'title': 'Song', 'audioPath': audio.path};
      final playlist = {
        'ytid': playlistId,
        'title': 'Offline list',
        'list': [song],
      };

      userOfflineSongs.value = [song];
      offlinePlaylistService.offlinePlaylists.value = [playlist];
      addTearDown(() async {
        userOfflineSongs.value = [];
        offlinePlaylistService.offlinePlaylists.value = [];
        await offlinePlaylistService.validateStoredPlaylists();
      });

      await tester.runAsync(offlinePlaylistService.validateStoredPlaylists);
      expect(offlinePlaylistService.isPlaylistUnavailable(playlistId), isTrue);

      await tester.pumpWidget(
        localizedApp(
          Scaffold(
            body: PlaylistDownloadButton(
              playlistId: playlistId,
              resolvePlaylist: () async => playlist,
              songs: [song],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byIcon(FluentIcons.arrow_download_24_filled),
        findsOneWidget,
      );
      expect(
        find.byIcon(FluentIcons.arrow_download_off_24_filled),
        findsNothing,
      );

      // Once the missing audio file is restored, validation marks it offline again.
      audio.writeAsStringSync('restored audio');
      await tester.runAsync(offlinePlaylistService.validateStoredPlaylists);
      await tester.pump();

      expect(offlinePlaylistService.isPlaylistUnavailable(playlistId), isFalse);
      expect(
        find.byIcon(FluentIcons.arrow_download_off_24_filled),
        findsOneWidget,
      );
    },
  );
}
