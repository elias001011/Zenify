import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/now_playing/wave_visualizer.dart';
import 'package:rxdart/rxdart.dart';

class _SessionPlayer extends AudioPlayer {
  final sessions = BehaviorSubject<int?>.seeded(42);
  @override
  Stream<int?> get androidAudioSessionIdStream => sessions.stream;
}

class _Handler extends MusifyAudioHandler {
  final _player = _SessionPlayer();
  @override
  AudioPlayer get audioPlayer => _player;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('zenify/audio_levels');
  const frames = MethodChannel('zenify/audio_levels/frames');
  late Directory dir;
  var permission = false;
  var listens = 0;
  var cancels = 0;
  Completer<void>? releasing;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('zenify_waves');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  setUp(() {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    permission = false;
    listens = cancels = 0;
    releasing = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(methods, (
      call,
    ) async {
      if (call.method == 'requestPermission') permission = true;
      return permission;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(frames, (
      call,
    ) async {
      if (call.method == 'listen') listens++;
      if (call.method == 'cancel') {
        cancels++;
        await releasing?.future;
      }
      return null;
    });
    audioHandler = _Handler();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    showPlayerVisualizer.value = true;
    floatingEffect.value = FloatingEffect.solid;
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    showPlayerVisualizer.value = false;
    floatingEffect.value = FloatingEffect.solid;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(methods, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(frames, null);
  });

  List<double> heights(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(WaveVisualizer),
        matching: find.byType(CustomPaint),
      ),
    );
    // Compare the rendered bar heights, without depending on their waveform.
    return List<double>.of((paint.painter as dynamic).heights as List<double>);
  }

  Future<void> advance(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  Future<void> frame(WidgetTester tester) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      frames.name,
      const StandardMethodCodec().encodeSuccessEnvelope([
        0.8,
        0.4,
        0.6,
        0.2,
        0.1,
        0.1,
      ]),
      (_) {},
    );
    await tester.pump();
  }

  Widget wave() => const MaterialApp(
    home: Scaffold(body: WaveVisualizer(size: 40, compact: true)),
  );

  testWidgets('compact waves move once per reading and never in between', (
    tester,
  ) async {
    permission = true;
    audioHandler.playbackState.add(PlaybackState(playing: true));
    await tester.pumpWidget(wave());
    await advance(tester);
    expect(listens, 1);
    final before = heights(tester);
    await frame(tester);
    // The one frame this reading asked for.
    await tester.pump();
    expect(heights(tester), isNot(before));
    expect(tester.binding.hasScheduledFrame, isFalse);

    audioHandler.playbackState.add(PlaybackState());
    await tester.pump();
    final paused = heights(tester);
    await advance(tester);
    expect(heights(tester), paused);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox());
    // Let the shared reader finish releasing before the next test.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(cancels, 1);
    debugDefaultTargetPlatformOverride = null;
  });
}
