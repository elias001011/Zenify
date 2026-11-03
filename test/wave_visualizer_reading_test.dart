import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/widgets/now_playing/wave_visualizer.dart';

import 'support/wave_test_handler.dart';
import 'wave_visualizer_test.dart' show heights;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  useTestSettings();
  testWidgets('waves stop hidden and in background', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final handler = WaveTestHandler()..ready();
    audioHandler = handler;
    Widget app(bool enabled) => MaterialApp(
      home: TickerMode(
        enabled: enabled,
        child: const WaveVisualizer(size: 100),
      ),
    );
    await tester.pumpWidget(app(true));
    await tester.pump(const Duration(milliseconds: 200));
    for (final enabled in [false, true]) {
      await tester.pumpWidget(app(enabled));
      final before = heights(tester);
      await tester.pump(const Duration(milliseconds: 200));
      expect(heights(tester), enabled ? isNot(before) : before);
    }
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    final background = heights(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(heights(tester), background);
    expect(tester.binding.hasScheduledFrame, isFalse);
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(heights(tester), isNot(background));
    await tester.pumpWidget(const SizedBox());
    await handler.playbackState.close();
    await handler.mediaItem.close();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop waves keep moving while the window is not in focus', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    final handler = WaveTestHandler()..ready();
    audioHandler = handler;
    await tester.pumpWidget(const MaterialApp(home: WaveVisualizer(size: 100)));
    await tester.pump(const Duration(milliseconds: 200));

    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    final unfocused = heights(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(heights(tester), isNot(unfocused));

    // Minimised: out of view, so the waves rest.
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    final hidden = heights(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(heights(tester), hidden);

    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
    await handler.playbackState.close();
    await handler.mediaItem.close();
    debugDefaultTargetPlatformOverride = null;
  });
}
