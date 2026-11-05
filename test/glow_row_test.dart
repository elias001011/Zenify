import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/artwork_glow.dart';
import 'package:musify/widgets/glow_row.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings(boxes: ['settings']);

  Widget row() => MaterialApp(
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

  testWidgets('phones get no arrows', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(row());
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
