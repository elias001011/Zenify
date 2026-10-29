import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
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

class _TrackedPlayer extends MediaKitPlayer {
  _TrackedPlayer(super.id);
  final filterEdits = <List<String>>[];
  @override
  Future<void> mpvCommand(List<String> args) {
    if (args.first == 'af') filterEdits.add(args);
    return super.mpvCommand(args);
  }
}

void main() {
  final library = Platform.environment['MUSIFY_TEST_LIBMPV'];
  test(
    'levels follow tracks and speed without editing the playing filter chain',
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
      final previousFilters = JustAudioMediaKit.audioFilters;
      final previousPitch = JustAudioMediaKit.pitch;
      addTearDown(() {
        JustAudioMediaKit.audioFilters = previousFilters;
        JustAudioMediaKit.pitch = previousPitch;
      });
      AudioLevels.configureDesktop();

      final wav = File('${dir.path}/beats.wav')..writeAsBytesSync(beatsWav());
      final player = _TrackedPlayer('levels');
      var released = false;
      addTearDown(() async {
        if (!released) await player.release();
      });
      await player.ready();
      await player.setMpvProperty('ao', 'null');
      expect(await AudioLevels.available, isTrue);

      final preparedChain = await player.getMpvProperty('af');
      expect(preparedChain, contains('amerge'));
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
      expect(player.filterEdits, isEmpty);
      expect(levels.map((level) => level.onset), contains(greaterThan(0.3)));
      expect(levels.map((level) => level.loud), contains(lessThan(0.6)));
      // The bass hits come and go; the 3 kHz tone in the mids stays put.
      double spread(int band) {
        final values = [for (final level in levels) level.bands[band]];
        return values.reduce(max) - values.reduce(min);
      }

      expect(spread(0), greaterThan(spread(3) + 0.3));

      // Native speed control must preserve the prepared analysis chain.
      final beforeSpeed = levels.length;
      await player.setSpeed(SetSpeedRequest(speed: 1.25));
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      expect(levels.length, greaterThan(beforeSpeed + 5));
      final chain = await player.getMpvProperty('af');
      expect(chain, preparedChain);
      expect(await player.getMpvProperty('speed'), '1.250000');
      expect(await player.getMpvProperty('audio-pitch-correction'), 'yes');
      expect(chain, contains('amerge'));

      // Identical readings are valid for silence, not a lost stream. Switch
      // files on the same engine before exercising an engine replacement.
      final silence = File('${dir.path}/silence.wav')
        ..writeAsBytesSync(silentWav(size: 64000));
      await player.load(
        LoadRequest(
          audioSourceMessage: ProgressiveAudioSourceMessage(
            id: 'silence',
            uri: silence.uri.toString(),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final silenceStart = levels.length;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(levels.length, greaterThan(silenceStart + 10));
      expect(
        levels.skip(silenceStart).map((v) => v.loud),
        everyElement(lessThan(0.01)),
      );

      // just_audio can replace its native player during a source change.
      // Both visualizers must keep receiving levels through that replacement.
      await player.release();
      released = true;
      final replacement = _TrackedPlayer('replacement');
      addTearDown(replacement.release);
      await replacement.ready();
      await replacement.setMpvProperty('ao', 'null');
      await replacement.load(
        LoadRequest(
          audioSourceMessage: ProgressiveAudioSourceMessage(
            id: 'replacement-beats',
            uri: wav.uri.toString(),
          ),
        ),
      );
      await replacement.play(PlayRequest());
      final beforeReplacement = levels.length;
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      expect(levels.length, greaterThan(beforeReplacement + 10));

      await subscription.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      final chainAfterCancel = await replacement.getMpvProperty('af');
      expect(chainAfterCancel, preparedChain);
      final again = AudioLevels.listen().listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(await replacement.getMpvProperty('af'), chainAfterCancel);
      await again.cancel();
      expect(replacement.filterEdits, isEmpty);
    },
    skip: library == null
        ? 'Set MUSIFY_TEST_LIBMPV to run the native level reader check'
        : false,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
