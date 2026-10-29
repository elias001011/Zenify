import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:just_audio_media_kit/mediakit_player.dart';
import 'package:media_kit/media_kit.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_levels.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/listening_stats_utils.dart';

import '../support/audio_fixture.dart';

void main() {
  final library = Platform.environment['MUSIFY_TEST_LIBMPV'];
  test(
    'opening and closing waves preserves native playback and recap counting',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      NativePlayer.test = true;
      JustAudioMediaKit.ensureInitialized(libmpv: library);
      AudioLevels.configureDesktop();
      final dir = await Directory.systemTemp.createTemp('zenify_wave_playback');
      Hive.init(dir.path);
      for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
        await Hive.openBox(box);
      }
      addTearDown(() async {
        await audioHandler.stop();
        await audioHandler.audioPlayer.dispose();
        await listeningStatsService.flush();
        await Hive.close();
        await dir.delete(recursive: true);
      });
      wrappedEnabled.value = true;
      offlineMode.value = true;
      await listeningStatsService.clearStats();
      audioHandler = MusifyAudioHandler();
      await audioHandler.setVolume(0);
      final wav = File('${dir.path}/beats.wav')
        ..writeAsBytesSync(beatsWav(seconds: 8));
      await audioHandler.addPlaylistToQueue([
        {
          'ytid': 'fixture',
          'title': 'Fixture',
          'artist': 'Test',
          'audioPath': wav.path,
          'isLive': false,
        },
      ], replace: true);
      await audioHandler.skipToSong(0);
      await audioHandler.pause();
      final native = MediaKitPlayer.latest!;
      await native.setMpvProperty('ao', 'null');
      final chain = await native.getMpvProperty('af');
      int total() =>
          listeningStatsService.monthStats(
                listeningStatsMonthKey(DateTime.now()),
              )?['totalSeconds']
              as int? ??
          0;
      final before = total();
      final stopwatch = Stopwatch()..start();
      await audioHandler.play();
      for (var i = 0; i < 4; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final subscription = AudioLevels.listen().listen((_) {});
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await subscription.cancel();
        expect(audioHandler.audioPlayer.playing, isTrue);
        expect(audioHandler.audioPlayer.processingState, ProcessingState.ready);
        expect(await native.getMpvProperty('af'), chain);
      }
      await audioHandler.pause();
      final heard = total() - before;
      expect(heard, inInclusiveRange(3, stopwatch.elapsed.inSeconds + 1));
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      listeningStatsService.recordListeningSessionProgress(wasPlaying: true);
      expect(total() - before, heard);
    },
    skip: library == null
        ? 'Set MUSIFY_TEST_LIBMPV for the native playback check'
        : false,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
