import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/playlist_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/edit_playlist_dialog.dart';
import 'package:musify/widgets/playlist_page/empty_playlist_state.dart';
import 'package:musify/widgets/song_bar.dart';

Map playlist(String id, {List<String> ids = const ['a', 'b', 'c']}) => {
  'ytid': id,
  'title': 'Playlist $id',
  'source': 'user-created',
  'list': [
    for (final id in ids)
      {'ytid': id, 'title': 'Track $id', 'artist': 'Artist'},
  ],
};

class _Handler extends MusifyAudioHandler {
  final added = <String>[];
  @override
  Future<void> addToQueue(Map song, {bool playNext = false}) async =>
      added.add(song['ytid']);
}

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('zenify_playlist_edit');
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });
  setUp(() {
    offlineMode.value = true;
    userCustomPlaylists.value = [playlist('source')];
    userPlaylistFolders.value = [
      {
        'id': 'folder',
        'name': 'Folder',
        'playlists': [
          playlist('target', ids: ['b']),
        ],
      },
    ];
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    audioHandler = _Handler();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: PlaylistPage(playlistData: userCustomPlaylists.value.single),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.scrollUntilVisible(
      find.byType(SongBar).first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }

  testWidgets(
    'editing a sorted playlist is handed its stored order, not the sort',
    (tester) async {
      await mount(tester);
      await tester.ensureVisible(find.text('Date Added'));
      await tester.tap(find.text('Date Added'));
      await tester.pump();
      expect(
        tester.getTopLeft(find.text('Track c')).dy,
        lessThan(tester.getTopLeft(find.text('Track a')).dy),
      );

      await tester.ensureVisible(find.byIcon(FluentIcons.edit_24_filled));
      await tester.tap(find.byIcon(FluentIcons.edit_24_filled));
      await tester.pump(const Duration(milliseconds: 300));
      // What the dialog hands back is saved as the playlist.
      final dialog = tester.widget<EditPlaylistDialog>(
        find.byType(EditPlaylistDialog),
      );
      expect((dialog.playlistData['list'] as List).map((s) => s['ytid']), [
        'a',
        'b',
        'c',
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    },
  );

  testWidgets('every playlist opens in its own order', (tester) async {
    await mount(tester);
    await tester.ensureVisible(find.text('Date Added'));
    await tester.tap(find.text('Date Added'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await mount(tester);
    expect(
      tester.getTopLeft(find.text('Track a')).dy,
      lessThan(tester.getTopLeft(find.text('Track c')).dy),
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets(
    'a playlist that fails to load shows its error without breaking',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      audioHandler = _Handler();
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlaylistPage(playlistId: 'PLmissing'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(EmptyPlaylistState), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    },
  );
}
