import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/playlist_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/song_bar.dart';
import 'package:musify/widgets/song_selection_bar.dart';

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
    playlistSortSetting = 'default_';
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

  test('reorder preserves the canonical list and latest metadata in root and folder', () async {
    final root = userCustomPlaylists.value.single;
    final songs = root['list'] as List;
    final requested = [songs[2], songs[0], songs[1]];
    songs[0] = Map<String, String>.from(songs[0])..['title'] = 'Renamed';
    expect(reorderCustomPlaylist('source', requested), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final stored = (Hive.box('user').get('customPlaylists') as List).single;
    expect((stored['list'] as List).map((s) => s['ytid']), ['c', 'a', 'b']);
    expect(stored['list'][1]['title'], 'Renamed');
    expect(reorderCustomPlaylist('source', [requested.first]), isFalse);
    expect(
      reorderCustomPlaylist('source', [
        requested.first,
        requested.first,
        requested.first,
      ]),
      isFalse,
    );
    expect(
      reorderCustomPlaylist('target', [
        playlist('x', ids: ['b'])['list'][0],
      ]),
      isTrue,
    );
  });

  test(
    'moving across folders preserves selection order and handles duplicates',
    () async {
      final source = userCustomPlaylists.value.single;
      final songs = source['list'] as List;
      expect(
        await moveSongsToCustomPlaylist('source', 'target', [
          songs[2],
          songs[1],
        ]),
        2,
      );
      expect((source['list'] as List).map((s) => s['ytid']), ['a']);
      final storedFolders = Hive.box('user').get('playlistFolders') as List;
      final targetSongs = storedFolders.single['playlists'][0]['list'] as List;
      expect(targetSongs.map((s) => s['ytid']), ['b', 'c']);
      expect(
        await moveSongsToCustomPlaylist('source', 'source', [songs.first]),
        0,
      );
    },
  );

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
    'long press selects songs, checkbox taps preserve order when queueing',
    (tester) async {
      await mount(tester);
      await tester.longPress(find.text('Track c'));
      await tester.pump();
      await tester.tap(find.text('Track a'));
      await tester.pump();
      expect(find.byType(SongSelectionBar), findsOneWidget);
      expect(find.text('2 songs selected'), findsOneWidget);
      expect(find.byType(ReorderableDragStartListener), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Add to queue'));
      await tester.pump();
      expect((audioHandler as _Handler).added, ['c', 'a']);
      expect(find.byType(SongSelectionBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    },
  );

  testWidgets(
    'manual reorder uses final insertion index and search hides handles',
    (tester) async {
      await mount(tester);
      await tester.runAsync(() async {
        tester
            .widget<SliverReorderableList>(find.byType(SliverReorderableList))
            .onReorderItem!(0, 2);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await Hive.box('user').flush();
      });
      await tester.pump();
      expect(
        (userCustomPlaylists.value.single['list'] as List).map(
          (s) => s['ytid'],
        ),
        ['b', 'c', 'a'],
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    },
  );
}
