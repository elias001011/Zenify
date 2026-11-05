import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/theme/app_themes.dart';
import 'package:musify/utilities/playlist_dialogs.dart';
import 'package:musify/widgets/edit_playlist_dialog.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings();

  for (final size in [const Size(390, 844), const Size(2560, 1440)]) {
    testWidgets('playlist dialogs stay readable at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      userCustomPlaylists.value = [
        {
          'ytid': 'custom:a',
          'source': 'user-created',
          'title': 'Playlist one',
          'list': [],
        },
      ];
      late BuildContext page;
      await tester.pumpWidget(
        MaterialApp(
          theme: getAppTheme(ColorScheme.fromSeed(seedColor: Colors.blue)),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              page = context;
              return const Scaffold();
            },
          ),
        ),
      );
      for (final open in <VoidCallback>[
        () => showAddToPlaylistDialog(
          page,
          song: {'ytid': 'song', 'title': 'Song'},
        ),
        () => showCreatePlaylistDialog(page),
        () {
          showDialog<void>(
            context: page,
            builder: (_) => EditPlaylistDialog(
              playlistData: userCustomPlaylists.value.first,
            ),
          );
        },
      ]) {
        open();
        await tester.pumpAndSettle();
        final surface = find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Material),
            )
            .first;
        final rect = tester.getRect(surface);
        expect(rect.width, lessThanOrEqualTo(560));
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(tester.takeException(), isNull);
        Navigator.of(page).pop();
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
