import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:just_audio_media_kit/mediakit_player.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:media_kit/media_kit.dart';
import 'package:musify/services/mix_effects.dart';

import '../support/app_harness.dart';
import '../support/audio_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppSettings(inMemory: true);
  final library = Platform.environment['MUSIFY_TEST_LIBMPV'];
  test(
    'libmpv takes the Mix filters, a retuned echo and a transition of commands',
    () async {
      final previous = NativePlayer.test;
      NativePlayer.test = true;
      addTearDown(() => NativePlayer.test = previous);
      MediaKit.ensureInitialized(libmpv: library);
      final directory = await Directory.systemTemp.createTemp('mix-effects');
      addTearDown(() => directory.delete(recursive: true));
      final file = await File('${directory.path}/beats.wav')
          .writeAsBytes(beatsWav(seconds: 20));
      JustAudioMediaKit.pitch = false;
      JustAudioMediaKit.audioFilters = MixEffects.desktopFilters;
      final player = MediaKitPlayer('mix-effects');
      addTearDown(player.release);
      await player.ready();
      await player.setMpvProperty('ao', 'null');
      await player.load(
        LoadRequest(
          audioSourceMessage: ProgressiveAudioSourceMessage(
            id: 'beats',
            uri: file.uri.toString(),
            headers: {},
          ),
        ),
      );
      final filters = await player.getMpvProperty('af');
      for (final label in ['zmixhp', 'zmixlp', 'zmixe']) {
        expect(filters, contains(label));
      }
      // As MixEffects.tuneEcho does on a loaded, silent player: 160 BPM.
      expect(MixEffects.echoDelay(160), 375);
      await player.mpvCommand(['af', 'remove', '@zmixe']);
      await player.mpvCommand([
        'af',
        'add',
        MixEffects.desktopFilters.last.replaceFirst(
          '500|1000|1500',
          '375|750|1125',
        ),
      ]);
      expect(await player.getMpvProperty('af'), contains('375|750|1125'));
      await player.play(PlayRequest());
      // A second of a transition, at the engine's pace.
      for (var i = 0; i <= 20; i++) {
        final t = i / 20;
        for (final command in [
          ['zmixhp', 'f', '${(20 + 1480 * t).round()}', 'highpass'],
          ['zmixlp', 'f', '${(300 + 10000 * (1 - t)).round()}', 'lowpass'],
          ['zmixl', 'gain', (-24 * t).toStringAsFixed(1), 'bass'],
          ['zmixe', 'volume', '${1 - t}', 'volume'],
          ['zmixe', 'weights', '1 ${0.7 * t}', 'amix'],
        ]) {
          await player.mpvCommand(['af-command', ...command]);
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(await player.getMpvProperty('af'), contains('zmixe'));
    },
    skip: library == null ? 'Set MUSIFY_TEST_LIBMPV' : false,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
