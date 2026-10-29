import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/settings_manager.dart';

import '../support/audio_fixture.dart';

void main() {
  final library = Platform.environment['MUSIFY_TEST_LIBMPV'];
  test(
    'restart restores a paused queue and resumes its local source at the saved position',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      NativePlayer.test = true;
      JustAudioMediaKit.ensureInitialized(libmpv: library);
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final directory = await Directory.systemTemp.createTemp(
        'zenify_queue_native',
      );
      Hive.init(directory.path);
      for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
        await Hive.openBox(name);
      }
      addTearDown(() async {
        await Future<void>.delayed(const Duration(seconds: 2));
        await Hive.close();
        await directory.delete(recursive: true);
      });
      final wav = File('${directory.path}/music.wav')
        ..writeAsBytesSync(silentWav(size: 320000));
      offlineMode.value = true;
      playNextSongAutomatically.value = false;
      final original = MusifyAudioHandler();
      await original.setVolume(0);
      await original.addPlaylistToQueue([
        for (var i = 0; i < 3; i++)
          {
            'ytid': 'local$i',
            'title': 'Track $i',
            'artist': 'Artist',
            'audioPath': wav.path,
          },
      ]);
      await original.skipToSong(1);
      await original.pause();
      await original.seek(const Duration(seconds: 5));
      await original.stop();
      final ids = original.queue.value.map((song) => song.id).toList();
      await original.audioPlayer.dispose();

      final restored = MusifyAudioHandler();
      await restored.setVolume(0);
      expect(restored.queue.value.map((song) => song.id), ids);
      expect(restored.currentQueueIndex, 1);
      expect(restored.audioPlayer.audioSource, isNull);
      expect(restored.audioPlayer.playing, isFalse);
      expect(restored.currentPositionData.position.inSeconds, 5);
      await restored.play();
      expect(restored.currentQueueIndex, 1);
      expect(restored.audioPlayer.position.inMilliseconds, closeTo(5000, 500));
      await restored.stop();
      await restored.audioPlayer.dispose();
    },
    skip: library == null
        ? 'Set MUSIFY_TEST_LIBMPV to verify restoration with native playback'
        : false,
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
