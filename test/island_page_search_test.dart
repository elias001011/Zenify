import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/floating_island.dart';
import 'package:musify/widgets/floating_surface.dart';
import 'package:musify/widgets/spinner.dart';

import 'support/app_harness.dart';

/// What a page hands the island for its own search field, and what the island
/// reports back.
class _PageSearch {
  final controller = TextEditingController();
  final focusNode = FocusNode();
  final loading = ValueNotifier(false);
  final changed = <String>[];
  final submitted = <String>[];

  late final value = IslandPageSearch(
    controller: controller,
    focusNode: focusNode,
    loading: loading,
    onChanged: changed.add,
    onSubmitted: submitted.add,
  );

  void dispose() {
    controller.dispose();
    focusNode.dispose();
    loading.dispose();
  }
}

Widget _page(IslandPageSearch search) => IslandScaffold(
  title: 'Search',
  globalSearch: false,
  pageSearch: search,
  body: const Text('Page body'),
);

/// The page pushed over a home page, so it has somewhere to go back to.
Widget _pushedFrom(IslandPageSearch search) => localizedApp(
  Builder(
    builder: (context) => Scaffold(
      body: TextButton(
        onPressed: () =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => _page(search))),
        child: const Text('Home page'),
      ),
    ),
  ),
);

void main() {
  useAppSettings();

  testWidgets('a page search shows its field at once, bound to the page', (
    tester,
  ) async {
    final page = _PageSearch();
    page.controller.text = 'Blue';
    await tester.pumpWidget(localizedApp(_page(page.value)));

    // The field is in the island, with no search button to open it first.
    final field = find.descendant(
      of: find.byType(FloatingSurface),
      matching: find.byType(TextField),
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(field, findsOneWidget);
    expect(find.byTooltip('Search'), findsNothing);
    expect(tester.widget<TextField>(field).controller, page.controller);
    expect(tester.widget<TextField>(field).focusNode, page.focusNode);
    expect(find.text('Blue'), findsOneWidget);

    page.controller.clear();
    await tester.pump();
    expect(find.text('Search'), findsOneWidget, reason: 'the hint');

    await tester.enterText(field, 'Blue hour');
    expect(page.changed, ['Blue hour']);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(page.submitted, ['Blue hour']);
    expect(page.controller.text, 'Blue hour');

    await tester.pumpWidget(const SizedBox());
    page.dispose();
  });

  testWidgets('the search icon turns into the spinner while it loads', (
    tester,
  ) async {
    final page = _PageSearch();
    await tester.pumpWidget(localizedApp(_page(page.value)));
    expect(find.byType(Spinner), findsNothing);
    expect(find.byIcon(FluentIcons.search_24_regular), findsOneWidget);

    page.loading.value = true;
    await tester.pump();
    expect(find.byType(Spinner), findsOneWidget);
    expect(find.byIcon(FluentIcons.search_24_regular), findsNothing);

    page.loading.value = false;
    await tester.pump();
    expect(find.byType(Spinner), findsNothing);
    expect(find.byIcon(FluentIcons.search_24_regular), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    page.dispose();
  });

  testWidgets(
    'the clear button empties the text, tells the page, keeps focus',
    (tester) async {
      final page = _PageSearch();
      await tester.pumpWidget(localizedApp(_page(page.value)));
      expect(find.byTooltip('Clear'), findsNothing, reason: 'nothing to clear');

      await tester.enterText(find.byType(TextField), 'Blue hour');
      await tester.pump();
      page.focusNode.unfocus();
      await tester.pump();
      expect(page.focusNode.hasFocus, isFalse);

      await tester.tap(find.byTooltip('Clear'));
      await tester.pump();
      expect(page.controller.text, isEmpty);
      expect(page.changed.last, '');
      expect(page.focusNode.hasFocus, isTrue);
      // Clearing is not leaving: the field stays, and the button goes.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip('Clear'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      page.dispose();
    },
  );

  testWidgets('Escape only leaves the field; one Back leaves the page', (
    tester,
  ) async {
    final page = _PageSearch();
    await tester.pumpWidget(_pushedFrom(page.value));
    await tester.tap(find.text('Home page'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Blue hour');
    expect(page.focusNode.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(page.focusNode.hasFocus, isFalse);
    expect(page.controller.text, 'Blue hour');
    expect(find.byType(TextField), findsOneWidget);
    expect(page.changed, ['Blue hour'], reason: 'Escape is not a clear');

    // The page search never closes: the first Back already leaves the page.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Page body'), findsNothing);
    expect(find.text('Home page'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    page.dispose();
  });

  testWidgets('a pushed page search has a Back button, a first one has none', (
    tester,
  ) async {
    final page = _PageSearch();
    await tester.pumpWidget(localizedApp(_page(page.value)));
    expect(find.byTooltip('Back'), findsNothing);
    await tester.pumpWidget(const SizedBox());

    await tester.pumpWidget(_pushedFrom(page.value));
    await tester.tap(find.text('Home page'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Page body'), findsNothing);
    expect(find.text('Home page'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    page.dispose();
  });

  testWidgets(
    'the island filter keeps its search button and Escape closes it',
    (tester) async {
      var filter = '';
      await tester.pumpWidget(
        localizedApp(
          IslandScaffold(
            title: 'Playlist',
            onFilter: (query) => filter = query,
            body: const Text('Page body'),
          ),
        ),
      );
      // Closed until the search button opens it.
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Blue hour');
      expect(filter, 'Blue hour');
      expect(find.byTooltip('Close'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(filter, '');
      expect(find.byTooltip('Search'), findsOneWidget);
    },
  );
}
