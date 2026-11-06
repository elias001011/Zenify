import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/artwork_glow.dart';
import 'package:musify/widgets/glow_row.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings(boxes: ['settings']);

  Widget row({TextDirection? direction}) => MaterialApp(
    builder: direction == null
        ? null
        : (context, child) =>
              Directionality(textDirection: direction, child: child!),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 500,
          height: 120,
          child: GlowRow(
            itemCount: 10,
            itemExtent: 136,
            itemBuilder: (context, index) =>
                SizedBox(width: 120, child: Text('item $index')),
          ),
        ),
      ),
    ),
  );

  testWidgets('desktop arrows follow the scroll position', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    floatingEffect.value = FloatingEffect.blurred;
    await tester.pumpWidget(row());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsOneWidget);
    // Glass is for the navigation, not for a button over artwork.
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byIcon(FluentIcons.chevron_left_24_regular), findsNothing);

    await tester.tap(find.byIcon(FluentIcons.chevron_right_24_regular));
    await tester.pumpAndSettle();

    expect(find.byIcon(FluentIcons.chevron_left_24_regular), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final direction in TextDirection.values) {
    testWidgets('arrows point away from the row\'s edges ($direction)', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await tester.pumpWidget(row(direction: direction));
      await tester.pump();

      // Where the arrow's glyph points on screen: its own face, flipped when
      // the icon follows the text direction.
      bool pointsLeft(Finder button) {
        final finder = find.descendant(of: button, matching: find.byType(Icon));
        final icon = tester.widget<Icon>(finder).icon!;
        final flipped =
            icon.matchTextDirection &&
            Directionality.of(tester.element(finder)) == TextDirection.rtl;
        return (icon == FluentIcons.chevron_left_24_regular) != flipped;
      }

      final buttons = find.byType(IconButton);
      final rtl = direction == TextDirection.rtl;
      // At the start only the arrow towards the end shows: on the right edge
      // in a right-to-left row, where it points left.
      expect(buttons, findsOneWidget);
      expect(pointsLeft(buttons), rtl);
      await tester.tap(buttons);
      await tester.pumpAndSettle();

      // Further in, one on each edge, each pointing outwards.
      expect(buttons, findsNWidgets(2));
      final firstIsLeft =
          tester.getCenter(buttons.at(0)).dx <
          tester.getCenter(buttons.at(1)).dx;
      final left = buttons.at(firstIsLeft ? 0 : 1);
      final right = buttons.at(firstIsLeft ? 1 : 0);
      expect(pointsLeft(left), isTrue);
      expect(pointsLeft(right), isFalse);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('phones get no arrows', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(row());
    await tester.pump();

    expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a tablet gets the arrows while a mouse is connected', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(row());
    await tester.pump();
    expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(5, 5));
    await tester.pump();
    expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsOneWidget);

    await mouse.removePointer();
    await tester.pump();
    expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('with the dynamic background off, glows ask for no frames', (
    tester,
  ) async {
    dynamicBackground.value = false;
    addTearDown(() => dynamicBackground.value = true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const SizedBox(height: 200, child: PageGlow(source: null)),
              Expanded(child: row()),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);

    // Turning it on brings the glow in.
    dynamicBackground.value = true;
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(seconds: 2));
  });
}
