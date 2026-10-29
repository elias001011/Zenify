import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_levels.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/settings_manager.dart';
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

  test(
    'native reader serializes release and is shared across listeners',
    () async {
      final first = AudioLevels.listen().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(listens, 1);
      final shared = AudioLevels.listen().listen((_) {});
      await shared.cancel();
      expect(cancels, 0);
      releasing = Completer<void>();
      await first.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(cancels, 1);
      final second = AudioLevels.listen().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(listens, 1);
      releasing!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(listens, 2);
      await second.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    },
  );
}
