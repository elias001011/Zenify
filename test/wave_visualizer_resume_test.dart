import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_levels.dart';
import 'package:musify/widgets/now_playing/wave_visualizer.dart';

import 'support/audio_levels_harness.dart';
import 'wave_visualizer_test.dart' show heights;

const _codec = StandardMethodCodec();

/// One reading of music: the overall level, then the five bands, with a beat
/// twice a second on the low ones.
List<double> _music(double seconds) {
  final beat = pow(max(0, sin(seconds * 4 * pi)), 6).toDouble();
  double band(int i, double base) =>
      base *
      (0.75 + 0.25 * sin(seconds * 3 + i)) *
      (i < 2 ? 1 + 0.9 * beat : 1);
  return [
    0.12,
    band(0, 0.20),
    band(1, 0.15),
    band(2, 0.10),
    band(3, 0.06),
    band(4, 0.03),
  ];
}

void main() {
  final h = AudioLevelsHarness()..install();
  setUp(AudioLevels.resetForTesting);

  void playing(bool value) => audioHandler.playbackState.add(
    PlaybackState(playing: value, processingState: AudioProcessingState.ready),
  );

  /// Pumps [milliseconds] of 16 ms frames, with a reading every 33 ms from
  /// [startAt] on (zeros for the first [zeros] ms), and returns the bars'
  /// average height after each frame.
  Future<List<double>> run(
    WidgetTester tester,
    int milliseconds, {
    bool feed = true,
    int startAt = 0,
    int zeros = 0,
  }) async {
    final series = <double>[];
    var lastReading = -100;
    for (var t = 0; t < milliseconds; t += 16) {
      await tester.pump(const Duration(milliseconds: 16));
      // The channel's answers need real time, not the test's.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      if (feed && t >= startAt && t - lastReading >= 33) {
        lastReading = t;
        unawaited(
          h.binding.defaultBinaryMessenger.handlePlatformMessage(
            'zenify/audio_levels/frames',
            _codec.encodeSuccessEnvelope(
              t < startAt + zeros
                  ? List<double>.filled(6, 0)
                  : _music(t / 1000),
            ),
            (_) {},
          ),
        );
      }
      series.add(heights(tester).reduce((a, b) => a + b) / 9);
    }
    return series;
  }

  /// The most the average fell below its own best so far.
  double drawdown(List<double> series) {
    var best = 0.0;
    var worst = 0.0;
    for (final value in series) {
      best = max(best, value);
      worst = max(worst, best - value);
    }
    return worst;
  }

  Future<void> start(WidgetTester tester) async {
    h.permission = true;
    playing(true);
    await tester.pumpWidget(const MaterialApp(home: WaveVisualizer(size: 100)));
    final steady = await run(tester, 2500);
    expect(h.listens, 1);
    expect(steady.last, greaterThan(0.4));
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets('a short pause keeps the reader, so the resume is not cold', (
    tester,
  ) async {
    await start(tester);
    playing(false);
    await run(tester, 1000, feed: false);
    playing(true);
    final resume = await run(tester, 800);
    // The same reader, no new one to set up: the bars go straight to the
    // music, without a step and without falling back.
    expect(h.listens, 1);
    expect(h.cancels, 0);
    expect(drawdown(resume.take(24).toList()), lessThan(0.02));
    expect(resume[24], greaterThan(0.35));
    await finish(tester);
  });

  testWidgets('a long pause lets the reader go; the resume waits for it', (
    tester,
  ) async {
    await start(tester);
    playing(false);
    await run(tester, 600, feed: false);
    await tester.pump(const Duration(seconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    expect(h.cancels, 1);

    playing(true);
    final resume = await run(tester, 1500, startAt: 300);
    expect(h.listens, 2);
    // At rest until the first reading, not on the bars' own motion with a
    // jump to the music afterwards.
    expect(resume.take(14).every((height) => height < 0.02), isTrue);
    expect(drawdown(resume), lessThan(0.08));
    expect(resume.last, greaterThan(0.4));
    await finish(tester);
  });

  testWidgets('readings of zeros while the reader warms up do not drop them', (
    tester,
  ) async {
    await start(tester);
    playing(false);
    await run(tester, 600, feed: false);
    await tester.pump(const Duration(seconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    playing(true);
    final resume = await run(tester, 1500, zeros: 200);
    expect(resume.take(12).every((height) => height < 0.02), isTrue);
    expect(drawdown(resume), lessThan(0.08));
    expect(resume.last, greaterThan(0.4));
    await finish(tester);
  });

  test(
    'the first reading is not read as the loudest, and a pause keeps it',
    () async {
      h.permission = true;
      AudioLevel? last;
      Future<void> feed(double band) async {
        unawaited(
          h.binding.defaultBinaryMessenger.handlePlatformMessage(
            'zenify/audio_levels/frames',
            _codec.encodeSuccessEnvelope([0.1, band, band, band, band, band]),
            (_) {},
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      Future<void> listenTo(void Function(AudioLevel) onLevel) async {
        final subscription = AudioLevels.listen().listen(onLevel);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        addTearDown(subscription.cancel);
      }

      final first = <AudioLevel>[];
      await listenTo(first.add);
      await feed(0.1);
      expect(first.single.bands.every((band) => band < 0.9), isTrue);

      // The same song after a pause: the peaks are the ones it had, so a
      // quieter reading is quieter than the first, not full again.
      await feed(0.1);
      final loud = first.last.bands.first;
      await AudioLevels.listen().listen((_) {}).cancel();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final again = <AudioLevel>[];
      await listenTo((level) => last = level);
      await feed(0.04);
      expect(last!.bands.first, lessThan(loud));
      again.clear();
    },
  );
}
