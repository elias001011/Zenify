import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/screens/export_playlists_page.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/widgets/playlist_bar.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings();

  testWidgets('lists the library and enables Export once something is ticked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    userLikedSongsList.value = [
      {'ytid': 'likedlikedl', 'title': 'Liked', 'artist': 'Me'},
    ];
    userCustomPlaylists.value = [
      {
        'ytid': 'customId-1',
        'title': 'Road trip',
        'source': 'user-created',
        'list': [
          {'ytid': 'customcusto', 'title': 'Song', 'artist': 'You'},
        ],
      },
    ];
    await tester.pumpWidget(localizedApp(const ExportPlaylistsPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Liked songs'), findsOneWidget);
    expect(find.text('Road trip'), findsOneWidget);
    FilledButton button() =>
        tester.widget(find.widgetWithText(FilledButton, 'Export'));
    expect(button().onPressed, isNull);

    await tester.tap(find.text('Road trip'));
    await tester.pump();
    expect(button().onPressed, isNotNull);

    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(
      tester
          .widgetList<Checkbox>(find.byType(Checkbox))
          .every((box) => box.value ?? false),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the island search filters the playlists and Select all only '
      'touches the ones shown', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    userLikedSongsList.value = [
      {'ytid': 'likedlikedl', 'title': 'Liked', 'artist': 'Me'},
    ];
    userCustomPlaylists.value = [
      for (final (id, title) in [
        ('customId-1', 'Road trip'),
        ('customId-2', 'Road home'),
        ('customId-3', 'Gym'),
      ])
        {
          'ytid': id,
          'title': title,
          'source': 'user-created',
          'list': [
            {'ytid': 'customcusto', 'title': 'Song', 'artist': 'You'},
          ],
        },
    ];
    await tester.pumpWidget(localizedApp(const ExportPlaylistsPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Gym'));
    await tester.pump();
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'ROAD');
    await tester.pumpAndSettle();
    expect(find.text('Road trip'), findsOneWidget);
    expect(find.text('Road home'), findsOneWidget);
    expect(find.text('Gym'), findsNothing);
    expect(find.text('Liked songs'), findsNothing);

    // Select all ticks what is shown and keeps what was ticked before.
    await tester.tap(find.text('Select all'));
    await tester.pump();
    Checkbox boxOf(String title) => tester.widget<Checkbox>(
      find.descendant(
        of: find.ancestor(
          of: find.text(title),
          matching: find.byType(PlaylistBar),
        ),
        matching: find.byType(Checkbox),
      ),
    );
    expect(boxOf('Road trip').value, isTrue);
    expect(boxOf('Road home').value, isTrue);
    // The Select all box itself is ticked now: a second tap unticks the two.
    await tester.tap(find.text('Select all'));
    await tester.pump();
    expect(boxOf('Road trip').value, isFalse);
    expect(boxOf('Road home').value, isFalse);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Nothing in your library matches.'), findsOneWidget);
    expect(find.text('Select all'), findsNothing);

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Gym'), findsOneWidget);
    // The one ticked before the filter is still ticked.
    expect(boxOf('Gym').value, isTrue);
    expect(find.text('Nothing in your library matches.'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}
