import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/audio_service.dart';

class WaveTestHandler extends BaseAudioHandler implements MusifyAudioHandler {
  void ready() => playbackState.add(
    PlaybackState(playing: true, processingState: AudioProcessingState.ready),
  );

  @override
  Future<void> skipToNext({bool playWhenReady = true}) async {}
  @override
  Future<void> skipToPrevious({bool playWhenReady = true}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The waves read the wave reading from the settings box.
void useTestSettings() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('zenify_waves');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
}
