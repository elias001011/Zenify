import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/playlist_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/keyboard_shortcuts_manager.dart';
import 'package:musify/services/local_sync/sync_merge.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/floating_island.dart';
import 'package:musify/widgets/song_bar.dart';
import 'package:musify/widgets/song_selection_bar.dart';

import 'support/app_harness.dart';

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
  useAppSettings();
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

  test('batch removal keeps tracks added since the page opened', () async {
    final snapshot = playlist('source');
    userCustomPlaylists.value = [
      playlist('source', ids: ['a', 'b', 'c', 'new']),
    ];

    expect(removeSongsFromPlaylist(snapshot, [snapshot['list'][0]]), 1);
    await Hive.box('user').flush();
    final stored = (Hive.box('user').get('customPlaylists') as List).single;
    expect((stored['list'] as List).map((song) => song['ytid']), [
      'b',
      'c',
      'new',
    ]);
    expect((snapshot['list'] as List).map((song) => song['ytid']), [
      'b',
      'c',
      'new',
    ]);
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

  test('a saved playlist cover survives reopen and Local Sync', () async {
    const cover = 'data:image/jpeg;base64,AA==';
    final source = userCustomPlaylists.value.single;
    final target =
        (userPlaylistFolders.value.single['playlists'] as List).single;

    expect(
      await updateCustomPlaylistMetadata('source', {
        'title': 'New cover',
        'image': cover,
        'list': [],
      }),
      isTrue,
    );
    expect(
      await updateCustomPlaylistMetadata('target', {
        'title': 'Folder cover',
        'image': cover,
      }),
      isTrue,
    );
    expect(source['title'], 'Playlist source');
    expect(target['title'], 'Playlist target');

    await Hive.box('user').close();
    final user = await Hive.openBox('user');
    final document = SyncDocument()
      ..capture(
        {
          'customPlaylists': user.get('customPlaylists'),
          'playlistFolders': user.get('playlistFolders'),
        },
        null,
        'device',
      );
    final synced = document.materialize();
    final root = (synced['customPlaylists'] as List).single;
    final folder = (synced['playlistFolders'] as List).single;
    final nested = (folder['playlists'] as List).single;
    expect(root['image'], cover);
    expect(root['list'], hasLength(3));
    expect(nested['image'], cover);
    expect(nested['list'], hasLength(1));
  });

  test('manual CSV rows keep their position across concurrent edits', () async {
    final stored = playlist(
      'source',
      ids: ['user-first', 'a', 'c', 'user-last'],
    );
    userCustomPlaylists.value = [stored];
    final count = await insertReviewedPlaylistSongs(
      'source',
      {
        0: {'ytid': 'a'},
        2: {'ytid': 'c'},
        3: {'ytid': 'removed'},
      },
      {
        1: {'ytid': 'b'},
        4: {'ytid': 'e'},
        5: {'ytid': 'c'},
      },
    );

    expect(count, 2);
    final saved = (Hive.box('user').get('customPlaylists') as List).single;
    expect((saved['list'] as List).map((song) => song['ytid']), [
      'user-first',
      'a',
      'b',
      'c',
      'e',
      'user-last',
    ]);
  });

  test('creating with a cover saves it with an empty song list', () async {
    const cover = 'data:image/jpeg;base64,AA==';
    final id = await createCustomPlaylist('New playlist', cover);
    await Hive.box('user').close();
    final user = await Hive.openBox('user');
    final saved = (user.get('customPlaylists') as List).last;
    expect(saved['ytid'], id);
    expect(saved['image'], cover);
    expect(saved['list'], isEmpty);
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

  testWidgets('moving keeps what changed in the source meanwhile', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      localizedApp(
        Builder(
          builder: (built) {
            context = built;
            return const SizedBox();
          },
        ),
      ),
    );
    // Lists read from storage hold any map, as here.
    Map editable(Map p) => {...p, 'list': List<dynamic>.of(p['list'] as List)};
    userCustomPlaylists.value = [
      editable(playlist('source', ids: ['a', 'b'])),
      editable(playlist('other', ids: [])),
    ];
    List<String> ids(Map playlist) => [
      for (final song in playlist['list'] as List) song['ytid'] as String,
    ];
    List<String> stored(String id) => ids(
      (Hive.box('user').get('customPlaylists') as List).firstWhere(
        (playlist) => playlist['ytid'] == id,
      ),
    );

    await tester.runAsync(() async {
      // An undo puts a removed song back while the move is being saved.
      final moving = moveSongsToCustomPlaylist('source', 'target', [
        {'ytid': 'a'},
      ]);
      addSongInCustomPlaylist(context, 'source', {
        'ytid': 'restored',
        'title': 'Track restored',
      }, indexToInsert: 1);
      await moving;
    });
    expect(stored('source'), ['restored', 'b']);

    await tester.runAsync(
      () => Future.wait([
        moveSongsToCustomPlaylist('source', 'target', [
          {'ytid': 'restored'},
        ]),
        moveSongsToCustomPlaylist('source', 'other', [
          {'ytid': 'b'},
        ]),
      ]),
    );
    expect(stored('source'), isEmpty);
    expect(stored('other'), ['b']);
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    audioHandler = _Handler();
    await tester.pumpWidget(
      localizedApp(
        PlaylistPage(playlistData: userCustomPlaylists.value.single),
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
      expect(find.byType(ReorderableDragStartListener), findsNothing);
      expect(find.byTooltip('Select songs'), findsNothing);
      expect(
        tester.widget<IslandScaffold>(find.byType(IslandScaffold)).actions,
        isEmpty,
      );
      await tester.ensureVisible(find.byTooltip('Reorder songs'));
      await tester.tap(find.byTooltip('Reorder songs'));
      await tester.pump();
      expect(find.byType(ReorderableDragStartListener), findsWidgets);
      await tester.ensureVisible(find.byTooltip('Finish reordering'));
      await tester.tap(find.byTooltip('Finish reordering'));
      await tester.pump();
      expect(find.byType(ReorderableDragStartListener), findsNothing);
      await tester.ensureVisible(find.byTooltip('Reorder songs'));
      await tester.tap(find.byTooltip('Reorder songs'));
      await tester.pump();

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
      tester.widget<IslandScaffold>(find.byType(IslandScaffold)).onFilter!(
        'Track b',
      );
      await tester.pump();
      expect(find.byType(ReorderableDragStartListener), findsNothing);
      tester.widget<IslandScaffold>(find.byType(IslandScaffold)).onFilter!('');
      await tester.pump();
      expect(find.byType(ReorderableDragStartListener), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    },
  );

  testWidgets('leaving the playlist by shortcut cancels the pending move', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    audioHandler = _Handler();
    dynamicBackground.value = false;
    addTearDown(() => dynamicBackground.value = true);
    final source = playlist('source', ids: ['a']);
    final target = playlist('target', ids: []);
    userCustomPlaylists.value = [source, target];
    userPlaylistFolders.value = [];

    final router = GoRouter(
      initialLocation: '/home/playlist/source',
      routes: [
        ShellRoute(
          builder: (_, _, child) => child,
          routes: [
            GoRoute(
              path: '/home',
              builder: (_, _) => const Scaffold(body: Text('Home')),
              routes: [
                GoRoute(
                  path: 'playlist/:id',
                  builder: (_, _) => PlaylistPage(playlistData: source),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    NavigationManager.router = router;
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (_, child) => GlobalShortcuts(child: child!),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Track a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to playlist'));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/home');
    expect(find.text('Playlist target'), findsOneWidget);

    await tester.tap(find.text('Playlist target'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(source['list'], hasLength(1));
    expect(target['list'], isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
