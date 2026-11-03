import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/widgets/now_playing/wave_visualizer.dart';

import 'support/wave_test_handler.dart';

List<double> heights(WidgetTester tester) => List<double>.of(
  (tester
                  .widget<CustomPaint>(
                    find.descendant(
                      of: find.byType(WaveVisualizer),
                      matching: find.byType(CustomPaint),
                    ),
                  )
                  .painter
              as dynamic)
          .heights
      as List<double>,
);

Widget wave() =>
    const MaterialApp(home: Scaffold(body: WaveVisualizer(size: 100)));

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  useTestSettings();
  late WaveTestHandler handler;
  final captureCalls = <String>[];
  const channels = [
    MethodChannel('zenify/audio_levels'),
    MethodChannel('zenify/audio_levels/frames'),
  ];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    audioHandler = handler = WaveTestHandler();
    captureCalls.clear();
    for (final channel in channels) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        captureCalls.add(call.method);
        return true;
      });
    }
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    for (final channel in channels) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    }
    await handler.playbackState.close();
    await handler.mediaItem.close();
  });

  testWidgets('reduced motion leaves waves still without an audio reader', (
    tester,
  ) async {
    handler.ready();
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: WaveVisualizer(size: 100),
        ),
      ),
    );
    await tester.pump();
    final before = heights(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(heights(tester), before);
    expect(captureCalls, isEmpty);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  /// Frames enough for the bars to settle.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('waves animate without audio access and settle on pause', (
    tester,
  ) async {
    handler.ready();
    await tester.pumpWidget(wave());
    final quiet = heights(tester);
    expect(quiet.length, 9);
    await tester.pump(const Duration(milliseconds: 100));
    final before = heights(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(heights(tester), isNot(before));
    expect(captureCalls, isEmpty);
    expect(find.byType(TextButton), findsNothing);

    // Paused: the bars come down to the quiet pose and rest, as if silent.
    handler.playbackState.add(
      PlaybackState(processingState: AudioProcessingState.ready),
    );
    await tester.pump();
    await settle(tester);
    expect(heights(tester), quiet);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(heights(tester), quiet);

    // Playing again: no jump, they simply start moving from where they rest.
    handler.ready();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 50));
    expect(heights(tester), isNot(quiet));
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('buffering, idle and completed settle the waves until ready', (
    tester,
  ) async {
    handler.ready();
    await tester.pumpWidget(wave());
    final quiet = heights(tester);
    await tester.pump(const Duration(milliseconds: 200));
    for (final state in [
      AudioProcessingState.buffering,
      AudioProcessingState.loading,
      AudioProcessingState.idle,
      AudioProcessingState.completed,
    ]) {
      handler.playbackState.add(
        PlaybackState(playing: true, processingState: state),
      );
      await tester.pump();
      await settle(tester);
      expect(heights(tester), quiet);
      expect(tester.binding.hasScheduledFrame, isFalse);
      // Back in play between the states, so each one is settled afresh.
      handler.ready();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 200));
    }
    handler.mediaItem.add(const MediaItem(id: 'next', title: 'Next'));
    handler.ready();
    await tester.pump();
    // The restarted ticker's first frame only sets its clock.
    await tester.pump(const Duration(milliseconds: 50));
    final before = heights(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(heights(tester), isNot(before));
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
