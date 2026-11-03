import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_levels.dart';
import 'package:musify/services/settings_manager.dart';

import 'support/audio_levels_harness.dart';

void main() {
  final h = AudioLevelsHarness()..install();
  test('the simple reading never asks for access or reads audio', () async {
    waveReading.value = WaveReading.simple;
    h.permission = true;
    expect(await AudioLevels.available, isFalse);
    expect(h.listens, 0);
  });

  test('the precise reading reads only once access is granted', () async {
    expect(await AudioLevels.available, isFalse);
    expect(await AudioLevels.requestAccess(), isTrue);
    expect(await AudioLevels.available, isTrue);
  });

  test(
    'native reader serializes release and is shared across listeners',
    () async {
      final first = AudioLevels.listen().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(h.listens, 1);
      final shared = AudioLevels.listen().listen((_) {});
      await shared.cancel();
      expect(h.cancels, 0);
      h.releasing = Completer<void>();
      await first.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(h.cancels, 1);
      final second = AudioLevels.listen().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(h.listens, 1);
      h.releasing!.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(h.listens, 2);
      // A stalled Visualizer can keep the same audio session. Recover it
      // without having to close either player UI or change that session.
      audioHandler.playbackState.add(PlaybackState(playing: true));
      await Future<void>.delayed(const Duration(milliseconds: 2400));
      expect(h.cancels, 2);
      expect(h.listens, 3);
      await second.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    },
  );
}
