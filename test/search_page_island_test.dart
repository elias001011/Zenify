import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/screens/search_page.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/custom_bar.dart';
import 'package:musify/widgets/floating_surface.dart';
import 'package:musify/widgets/song_bar.dart';

import 'support/app_harness.dart';

/// The search page keeps no field of its own: the island is its search field.
void main() {
  // The page writes the search history; in memory it finishes within the test.
  useAppSettings(inMemory: true);

  setUp(() {
    // Offline, a search is the library's, which needs no network.
    offlineMode.value = true;
    userLikedSongsList.value = [
      {'ytid': 'blue', 'title': 'Blue hour', 'artist': 'Aurora Vale'},
      {'ytid': 'sea', 'title': 'The Sea', 'artist': 'Night Drive'},
    ];
    userOfflineSongs.value = userLikedSongsList.value;
    searchHistoryNotifier.value = ['Blue hour', 'The Sea'];
  });
  tearDown(() => offlineMode.value = false);

  final field = find.descendant(
    of: find.byType(FloatingSurface),
    matching: find.byType(TextField),
  );
  final songs = find.byType(SongBar);

  Future<void> openPage(WidgetTester tester, {String? initialQuery}) async {
    await tester.pumpWidget(
      localizedApp(SearchPage(initialQuery: initialQuery)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the island holds the only field, bound to the page query', (
    tester,
  ) async {
    await openPage(tester);
    expect(find.byType(SearchBar), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(field, findsOneWidget);
    expect(find.byTooltip('Search'), findsNothing, reason: 'no button to open');

    // The history starts below the island, not under it.
    expect(
      tester.getTopLeft(find.byType(CustomBar).first).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byType(FloatingSurface)).dy,
      ),
    );

    // What is typed is what a submit searches.
    expect(songs, findsNothing);
    await tester.enterText(field, 'Blue');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: songs, matching: find.text('Blue hour')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: songs, matching: find.text('The Sea')),
      findsNothing,
    );
    expect(find.widgetWithText(TextField, 'Blue'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a history entry fills the island field and searches it', (
    tester,
  ) async {
    await openPage(tester);
    await tester.tap(find.widgetWithText(CustomBar, 'The Sea'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(FloatingSurface),
        matching: find.widgetWithText(TextField, 'The Sea'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: songs, matching: find.text('The Sea')),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('clear empties the field, brings the history back, keeps focus', (
    tester,
  ) async {
    await openPage(tester, initialQuery: 'Blue hour');
    expect(find.widgetWithText(TextField, 'Blue hour'), findsOneWidget);
    expect(songs, findsOneWidget);
    final focus = tester.widget<TextField>(field).focusNode!;
    expect(focus.hasFocus, isFalse, reason: 'a finished search unfocuses');

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    expect(focus.hasFocus, isTrue);
    expect(songs, findsNothing);
    expect(find.widgetWithText(CustomBar, 'The Sea'), findsOneWidget);
    expect(find.byTooltip('Clear'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'a phone keeps no focus listener and ignores the search request',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await openPage(tester, initialQuery: 'Blue hour');
        final focus = tester.widget<TextField>(field).focusNode!;

        requestSearchFocus();
        tester.binding.scheduleFrame();
        await tester.pump();
        await tester.pump();
        expect(focus.hasFocus, isFalse);
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'the initial query and the focus request reach the island field',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await openPage(tester, initialQuery: 'Blue hour');
        expect(tester.widget<TextField>(field).controller!.text, 'Blue hour');
        final focus = tester.widget<TextField>(field).focusNode!;
        expect(focus.hasFocus, isFalse);

        // The search shortcut, while the page is already there.
        requestSearchFocus();
        tester.binding.scheduleFrame(); // the app always has a frame coming
        await tester.pump();
        await tester.pump();
        expect(focus.hasFocus, isTrue);
        await tester.pumpWidget(const SizedBox());

        // The same request, made from another tab before the page exists.
        requestSearchFocus();
        await openPage(tester);
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
