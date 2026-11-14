import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:just_audio_media_kit/mediakit_player.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:media_kit/media_kit.dart';
import 'package:musify/services/mix_analysis.dart';
import 'package:musify/services/mix_effects.dart';

import '../support/app_harness.dart';
import '../support/audio_fixture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  useAppSettings(inMemory: true);
  final library = Platform.environment['MUSIFY_TEST_LIBMPV'];
  test(
    'native tempo correction preserves Mix and user EQ filters; decoder finds the beat',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final previous = NativePlayer.test;
      NativePlayer.test = true;
      addTearDown(() => NativePlayer.test = previous);
      MediaKit.ensureInitialized(libmpv: library);
      final directory = await Directory.systemTemp.createTemp('mix-native');
      addTearDown(() => directory.delete(recursive: true));
      final file = await File('${directory.path}/beats.wav')
          .writeAsBytes(beatsWav(seconds: 20));
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => directory.path,
      );
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        ),
      );
      JustAudioMediaKit.pitch = false;
      JustAudioMediaKit.audioFilters = [
        ...MixEffects.desktopFilters,
        ...MixEffects.userFilters,
      ];
      final player = MediaKitPlayer('mix-native');
      addTearDown(player.release);
      await player.ready();
      await player.setMpvProperty('ao', 'null');
      await player.load(
        LoadRequest(
          audioSourceMessage: ProgressiveAudioSourceMessage(
            id: 'beat',
            uri: file.uri.toString(),
            headers: {},
          ),
        ),
      );
      await player.setSpeed(SetSpeedRequest(speed: 0.96));
      expect(
        double.parse(await player.getMpvProperty('speed')),
        closeTo(0.96, 1e-5),
      );
      expect(await player.getMpvProperty('audio-pitch-correction'), 'yes');
      final filters = await player.getMpvProperty('af');
      expect(filters, contains('zmixl'));
      expect(filters, contains('zuser4'));
      await player.mpvCommand(['af-command', 'zmixl', 'gain', '-12', 'bass']);
      await player.mpvCommand([
        'af-command',
        'zuser0',
        'gain',
        '3',
        'equalizer',
      ]);
      await player.setSpeed(SetSpeedRequest(speed: 1));
      expect(await player.getMpvProperty('af'), contains('zuser4'));
      final decoded = await MixAnalyzer.decode(
        (source: file.path, headers: null),
        start: const Duration(seconds: -12),
        length: const Duration(seconds: 12),
      );
      expect(decoded, isNotNull);
      final edge = analyzeEdge(
        decoded!.samples,
        decoded.rate,
        offset: 8000,
        tail: true,
      );
      expect(edge.bpm, closeTo(120, 1));
      expect(edge.rhythmic, isTrue);
    },
    skip: library == null ? 'Set MUSIFY_TEST_LIBMPV' : false,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
