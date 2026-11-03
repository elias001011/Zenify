import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:rxdart/rxdart.dart';

class _SessionPlayer extends AudioPlayer {
  final sessions = BehaviorSubject<int?>.seeded(42);
  @override
  Stream<int?> get androidAudioSessionIdStream => sessions.stream;
}

class _Handler implements MusifyAudioHandler {
  @override
  final playbackState = BehaviorSubject.seeded(PlaybackState());
  @override
  final mediaItem = BehaviorSubject<MediaItem?>.seeded(null);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  final _player = _SessionPlayer();
  @override
  AudioPlayer get audioPlayer => _player;
}

class AudioLevelsHarness {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  static const methods = MethodChannel('zenify/audio_levels');
  static const frames = MethodChannel('zenify/audio_levels/frames');
  late Directory dir;
  var permission = false;
  var listens = 0;
  var cancels = 0;
  Completer<void>? releasing;

  void install() {
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
      waveReading.value = WaveReading.precise;
    });
    tearDown(() async {
      debugDefaultTargetPlatformOverride = null;
      showPlayerVisualizer.value = false;
      floatingEffect.value = FloatingEffect.solid;
      waveReading.value = WaveReading.simple;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(methods, null);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(frames, null);
    });
  }
}
