import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/screens/export_playlists_page.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/playlists_manager.dart';

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
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: ExportPlaylistsPage(),
      ),
    );
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
}
