import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/screens/user_songs_page.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/playlist_page/add_to_playlist_button.dart';

import 'support/app_harness.dart';

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
}
