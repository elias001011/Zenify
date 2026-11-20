import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/user_songs_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/playlist_page/add_to_playlist_button.dart';

import 'support/app_harness.dart';

class _Recorder extends MusifyAudioHandler {
  final played = <List>[];
  final shuffled = <List>[];

  @override
  Future<void> playPlaylistSong({
    Map? playlist,
    bool? shuffle,
    bool keepGoing = false,
    required int songIndex,
  }) async => played.add(List.of(playlist!['list'] as List));

  @override
  Future<void> addPlaylistToQueue(
    List<Map> songs, {
    bool replace = false,
    bool? shuffle,
    bool keepGoing = false,
    int? startIndex,
    String? playlistId,
  }) async => shuffled.add(List.of(songs));
}

void main() {
  useAppSettings();

  Widget page(String name) => localizedApp(UserSongsPage(page: name));

  for (final name in ['liked', 'recents', 'offline']) {
    testWidgets('$name offers adding its songs to a playlist, online only', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final songs = [
        for (var i = 0; i < 3; i++)
          {'ytid': 'song$i', 'title': 'Track $i', 'artist': 'Artist'},
      ];
      userLikedSongsList.value = songs;
      userRecentlyPlayed.value = songs;
      userOfflineSongs.value = songs;
      addTearDown(() => offlineMode.value = false);

      offlineMode.value = false;
      await tester.pumpWidget(page(name));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PlaylistAddToPlaylistButton), findsOneWidget);

      offlineMode.value = true;
      await tester.pump();
      expect(find.byType(PlaylistAddToPlaylistButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  }

  testWidgets('add button stays, disabled with a spinner, while it resolves', (
    tester,
  ) async {
    final gate = Completer<Map?>();
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: PlaylistAddToPlaylistButton(resolvePlaylist: () => gate.future),
        ),
      ),
    );
    final button = find.descendant(
      of: find.byType(PlaylistAddToPlaylistButton),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    expect(
      find.descendant(
        of: button,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );

    await tester.tap(button);
    await tester.pump();
    // The same button, not a bare spinner in its place.
    expect(button, findsOneWidget);
    expect(tester.widget<IconButton>(button).onPressed, isNull);
    expect(
      find.descendant(
        of: button,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    gate.complete(null);
    await tester.pump();
    expect(tester.widget<IconButton>(button).onPressed, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Play and Shuffle queue the whole list, as in Musify, '
      'whatever the filter hides', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final recorder = _Recorder();
    audioHandler = recorder;
    userLikedSongsList.value = [
      for (var i = 0; i < 3; i++)
        {'ytid': 'song$i', 'title': 'Track $i', 'artist': 'Artist'},
    ];
    await tester.pumpWidget(page('liked'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(FluentIcons.search_24_regular).first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'Track 1');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Track 0'), findsNothing);

    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.tap(find.text('Shuffle'));
    await tester.pump();
    expect(recorder.played.single, hasLength(3));
    expect(recorder.shuffled.single, hasLength(3));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
