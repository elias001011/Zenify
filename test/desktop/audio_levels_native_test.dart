import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:just_audio_media_kit/mediakit_player.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:media_kit/media_kit.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_levels.dart';
import 'package:musify/services/audio_service.dart';
import 'package:rxdart/rxdart.dart';

import '../support/audio_fixture.dart';

class _Playing extends MusifyAudioHandler {
  // The handler's own player stays idle; the levels only read while playing.
  @override
  BehaviorSubject<PlaybackState> get playbackState =>
      BehaviorSubject.seeded(PlaybackState(playing: true));
}

void main() {
  final library = Platform.environment['MUSIFY_TEST_LIBMPV'];
  test(
    'levels follow the beats, survive a speed change and leave mpv clean',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final dir = await Directory.systemTemp.createTemp('musify_levels');
      addTearDown(() => dir.delete(recursive: true));
      Hive.init(dir.path);
      for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
        await Hive.openBox(box);
      }
      addTearDown(Hive.close);
      audioHandler = _Playing();
      final previousMode = NativePlayer.test;
      NativePlayer.test = true;
      addTearDown(() => NativePlayer.test = previousMode);
      MediaKit.ensureInitialized(libmpv: library);

      final wav = File('${dir.path}/beats.wav')..writeAsBytesSync(beatsWav());
      final player = MediaKitPlayer('levels');
      addTearDown(player.release);
      await player.ready();
      await player.setMpvProperty('ao', 'null');
      expect(await AudioLevels.available, isTrue);

      final levels = <AudioLevel>[];
      final subscription = AudioLevels.listen().listen(levels.add);
      await player.load(
        LoadRequest(
          audioSourceMessage: ProgressiveAudioSourceMessage(
            id: 'beats',
            uri: wav.uri.toString(),
          ),
        ),
      );
      await player.setLoopMode(
        SetLoopModeRequest(loopMode: LoopModeMessage.one),
      );
      await player.play(PlayRequest());
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(levels.length, greaterThan(10));
      expect(levels.map((level) => level.onset), contains(greaterThan(0.3)));
      expect(levels.map((level) => level.loud), contains(lessThan(0.6)));

      // A speed change makes media_kit rewrite the filter chain.
      final beforeSpeed = levels.length;
      await player.setSpeed(SetSpeedRequest(speed: 1.25));
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      expect(levels.length, greaterThan(beforeSpeed + 5));
      final chain = await player.getMpvProperty('af');
      expect(chain, contains('scaletempo'));
      expect(chain, contains('aspectralstats'));

      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await player.getMpvProperty('af'), isNot(contains('zviz')));
    },
    skip: library == null
        ? 'Set MUSIFY_TEST_LIBMPV to run the native level reader check'
        : false,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
