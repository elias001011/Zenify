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
}
