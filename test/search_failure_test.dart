import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/screens/search_page.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/floating_surface.dart';

import 'support/app_harness.dart';

/// An online search that cannot reach YouTube says so; it does not look like a
/// search with no results. (A test has no network: every request fails.)
void main() {
  useAppSettings(inMemory: true);

  setUp(() {
    offlineMode.value = false;
    userLikedSongsList.value = [];
    userOfflineSongs.value = [];
    searchHistoryNotifier.value = [];
  });

  final field = find.descendant(
    of: find.byType(FloatingSurface),
    matching: find.byType(TextField),
  );

  testWidgets('a search that fails online shows a snackbar, once', (
    tester,
  ) async {
    await tester.pumpWidget(localizedApp(const SearchPage()));
    await tester.pumpAndSettle();
    await tester.enterText(field, 'Aurora');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    // The requests fail at once; the search gives up on a slow one after 15 s.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('The search failed. Check your connection and try again.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 20));
  });

  testWidgets('offline, nothing is searched online and nothing is reported', (
    tester,
  ) async {
    offlineMode.value = true;
    await tester.pumpWidget(localizedApp(const SearchPage()));
    await tester.pumpAndSettle();
    await tester.enterText(field, 'Aurora');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(
      find.text('The search failed. Check your connection and try again.'),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
