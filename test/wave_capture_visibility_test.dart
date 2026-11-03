
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/widgets/now_playing/wave_visualizer.dart';

import 'support/audio_levels_harness.dart';

void main() {
  final h = AudioLevelsHarness()..install();
  testWidgets('waves release native capture when covered or paused', (
    tester,
  ) async {
    h.permission = true;
    audioHandler.playbackState.add(
      PlaybackState(playing: true, processingState: AudioProcessingState.ready),
    );
    Widget wave(bool enabled) => Directionality(
      textDirection: TextDirection.ltr,
      child: TickerMode(
        enabled: enabled,
        child: const WaveVisualizer(size: 100),
      ),
    );
    Future<void> settleCapture() => tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpWidget(wave(true));
    await settleCapture();
    expect(h.listens, 1);
    await tester.pumpWidget(wave(false));
    await settleCapture();
    expect(h.cancels, 1);
    await tester.pumpWidget(wave(true));
    await settleCapture();
    expect(h.listens, 2);
    audioHandler.playbackState.add(
      PlaybackState(processingState: AudioProcessingState.ready),
    );
    await tester.pump();
    await settleCapture();
    expect(h.cancels, 2);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
