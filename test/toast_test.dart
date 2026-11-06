import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/theme/app_themes.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/widgets/floating_surface.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings(boxes: ['settings']);

  late BuildContext page;

  tearDown(() {
    ToastInset.bottom = 0;
    ToastInset.dock = null;
  });

  ThemeData theme() =>
      getAppTheme(ColorScheme.fromSeed(seedColor: Colors.teal));

  Future<void> open(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double safeBottom = 0,
    bool withKey = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.view.padding = FakeViewPadding(bottom: safeBottom);
    tester.view.viewPadding = FakeViewPadding(bottom: safeBottom);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: withKey ? toastMessengerKey : null,
        theme: theme(),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              page = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
  }

  Future<void> shown(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));
  }

  /// The snack bar's visible surface, without its margin.
  Rect toastRect(WidgetTester tester) => tester.getRect(
    find
        .descendant(of: find.byType(SnackBar), matching: find.byType(Material))
        .first,
  );

  testWidgets('shows the text', (tester) async {
    await open(tester);
    showToast(page, 'Saved');
    await shown(tester);
    expect(find.text('Saved'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('takes the look of the app theme', (tester) async {
    await open(tester);
    showToast(page, 'Saved');
    await shown(tester);
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(SnackBar),
            matching: find.byType(Material),
          )
          .first,
    );
    final colors = theme().colorScheme;
    expect(material.color, colors.surfaceContainer);
    expect(material.elevation, 0);
    expect(
      material.shape,
      isA<RoundedRectangleBorder>().having(
        (shape) => shape.borderRadius,
        'radius',
        BorderRadius.circular(24),
      ),
    );
    final icon = tester.widget<Icon>(
      find.descendant(of: find.byType(SnackBar), matching: find.byType(Icon)),
    );
    expect(icon.color, colors.primary);
  });

  testWidgets('the action runs once and takes the snack bar away', (
    tester,
  ) async {
    await open(tester);
    var pressed = 0;
    showToastWithButton(page, 'Removed', 'Undo', () => pressed++);
    await shown(tester);
    expect(find.text('Removed'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(pressed, 1);
    expect(find.text('Removed'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a context that is no longer mounted still shows the toast', (
    tester,
  ) async {
    await open(tester);
    late BuildContext route;
    unawaited(
      Navigator.of(page).push(
        MaterialPageRoute<void>(
          builder: (context) {
            route = context;
            return const Scaffold();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    Navigator.of(route).pop();
    await tester.pumpAndSettle();
    expect(route.mounted, isFalse);

    showToast(route, 'After the route');
    showToastWithButton(route, 'Also this', 'Undo', () {});
    await shown(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('After the route'), findsOneWidget);
  });

  testWidgets('without a messenger key it uses the context, or does nothing', (
    tester,
  ) async {
    await open(tester, withKey: false);
    showToast(page, 'Through the context');
    await shown(tester);
    expect(find.text('Through the context'), findsOneWidget);

    late BuildContext route;
    unawaited(
      Navigator.of(page).push(
        MaterialPageRoute<void>(
          builder: (context) {
            route = context;
            return const Scaffold();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    Navigator.of(route).pop();
    await tester.pumpAndSettle();
    showToast(route, 'Nowhere to go');
    showToastWithButton(route, 'Nowhere either', 'Undo', () {});
    await shown(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Nowhere to go'), findsNothing);
  });

  group('margin', () {
    testWidgets('clears what floats over the pages', (tester) async {
      await open(tester);
      ToastInset.bottom = 120;
      showToast(page, 'Saved');
      await shown(tester);
      final rect = toastRect(tester);
      expect(rect.bottom, lessThanOrEqualTo(844 - 120));
      // A small gap over the dock.
      expect(rect.bottom, closeTo(844 - 120 - 8, 0.5));
    });

    testWidgets('counts the inset from the window, safe area included', (
      tester,
    ) async {
      await open(tester, safeBottom: 34);
      ToastInset.bottom = 154;
      showToast(page, 'Saved');
      await shown(tester);
      expect(toastRect(tester).bottom, closeTo(844 - 154 - 8, 0.5));
    });

    testWidgets('keeps off the bottom edge when nothing floats', (
      tester,
    ) async {
      await open(tester, safeBottom: 34);
      showToast(page, 'Saved');
      await shown(tester);
      expect(
        toastRect(tester).bottom,
        lessThanOrEqualTo(844 - 34 - FloatingSurface.edgeMargin),
      );
      expect(toastRect(tester).bottom, closeTo(844 - 34 - 12 - 8, 0.5));
    });

    testWidgets('stands over a dock that keeps to the left', (tester) async {
      await open(tester, size: const Size(1280, 800));
      ToastInset.bottom = 120;
      ToastInset.dock = (left: FloatingSurface.edgeMargin, width: 420);
      showToast(page, 'Saved');
      await shown(tester);
      final rect = toastRect(tester);
      expect(rect.left, closeTo(FloatingSurface.edgeMargin, 0.5));
      expect(rect.width, closeTo(420, 0.5));
      expect(rect.bottom, closeTo(800 - 120 - 8, 0.5));
    });

    testWidgets('fills a dock that is narrower than the window', (
      tester,
    ) async {
      await open(tester, size: const Size(300, 800));
      ToastInset.dock = (left: FloatingSurface.edgeMargin, width: 276);
      showToast(page, 'Saved');
      await shown(tester);
      final rect = toastRect(tester);
      expect(rect.left, closeTo(FloatingSurface.edgeMargin, 0.5));
      expect(rect.right, closeTo(300 - FloatingSurface.edgeMargin, 0.5));
    });

    testWidgets('is at most 480 wide and centred on a wide window', (
      tester,
    ) async {
      await open(tester, size: const Size(1280, 800));
      showToast(page, 'Saved');
      await shown(tester);
      final rect = toastRect(tester);
      expect(rect.width, lessThanOrEqualTo(480));
      expect(rect.width, closeTo(480, 0.5));
      expect(rect.center.dx, closeTo(640, 0.5));
    });

    testWidgets('takes the window but its margins on a phone', (tester) async {
      await open(tester);
      showToastWithButton(page, 'Removed', 'Undo', () {});
      await shown(tester);
      final rect = toastRect(tester);
      expect(rect.width, closeTo(390 - FloatingSurface.edgeMargin * 2, 0.5));
      expect(rect.left, closeTo(FloatingSurface.edgeMargin, 0.5));
    });
  });

  testWidgets('a swipe down dismisses it', (tester) async {
    await open(tester);
    showToast(page, 'Saved');
    await shown(tester);
    expect(find.text('Saved'), findsOneWidget);

    await tester.drag(find.text('Saved'), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });
}
