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

Widget wave({bool compact = true}) => MaterialApp(
  home: Scaffold(body: WaveVisualizer(size: 100, compact: compact)),
);

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

  for (final compact in [true, false]) {
    testWidgets(
      '${compact ? 'compact' : 'full'} waves animate without audio access and freeze on pause',
      (tester) async {
        handler.ready();
        await tester.pumpWidget(wave(compact: compact));
        await tester.pump(const Duration(milliseconds: 100));
        final before = heights(tester);
        await tester.pump(const Duration(milliseconds: 200));
        expect(heights(tester), isNot(before));
        expect(captureCalls, isEmpty);
        expect(find.byType(TextButton), findsNothing);

        handler.playbackState.add(
          PlaybackState(processingState: AudioProcessingState.ready),
        );
        await tester.pump();
        final paused = heights(tester);
        await tester.pump(const Duration(seconds: 1));
        expect(heights(tester), paused);
        expect(tester.binding.hasScheduledFrame, isFalse);
        // The paused painter still has all of its wave bars.
        expect(paused.length, compact ? 7 : 9);

        handler.ready();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 50));
        expect(heights(tester), isNot(paused));
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('the simple thumbnail redraws 8 times a second, no more', (
    tester,
  ) async {
    handler.ready();
    await tester.pumpWidget(wave());
    var previous = heights(tester);
    var redraws = 0;
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 25));
      final now = heights(tester);
      if (!listEquals(now, previous)) redraws++;
      previous = now;
    }
    expect(redraws, 8);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('buffering, idle and completed freeze waves until ready', (
    tester,
  ) async {
    handler.ready();
    await tester.pumpWidget(wave());
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
      final resting = heights(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(heights(tester), resting);
      expect(tester.binding.hasScheduledFrame, isFalse);
    }
    handler.mediaItem.add(const MediaItem(id: 'next', title: 'Next'));
    handler.ready();
    await tester.pump();
    final before = heights(tester);
    await tester.pump(const Duration(milliseconds: 200));
    expect(heights(tester), isNot(before));
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
