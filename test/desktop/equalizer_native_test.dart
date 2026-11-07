import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:just_audio_media_kit/mediakit_player.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:media_kit/media_kit.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_levels.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/desktop_equalizer.dart';
import 'package:musify/services/settings_manager.dart';

import '../support/audio_fixture.dart';

void main() {
  final library = Platform.environment['MUSIFY_TEST_LIBMPV'];
  final skip = library == null
      ? 'Set MUSIFY_TEST_LIBMPV to run the native equalizer checks'
      : false;

  /// Opens the settings and libmpv for a test and returns its folder.
  Future<Directory> prepare() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final dir = await Directory.systemTemp.createTemp('musify_equalizer');
    addTearDown(() => dir.delete(recursive: true));
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box);
    }
    addTearDown(Hive.close);
    addTearDown(() {
      equalizerEnabled.value = false;
      equalizerBandGains.value = const [];
    });
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
    return dir;
  }

  Future<void> play(MediaKitPlayer player, File wav, {bool loop = true}) async {
    await player.load(
      LoadRequest(
        audioSourceMessage: ProgressiveAudioSourceMessage(
          id: wav.path,
          uri: wav.uri.toString(),
        ),
      ),
    );
    if (loop) {
      await player.setLoopMode(
        SetLoopModeRequest(loopMode: LoopModeMessage.one),
      );
    }
    await player.play(PlayRequest());
  }

  test(
    'the equalizer changes what libmpv plays, live and on a new engine',
    () async {
      final dir = await prepare();
      AudioLevels.configureDesktop();
      // The handler's methods are what the equalizer page calls.
      final handler = audioHandler = MusifyAudioHandler();

      final engines = <MediaKitPlayer>[];
      addTearDown(() async {
        for (final player in engines) {
          await player.release();
        }
      });
      Future<MediaKitPlayer> start(String id, File wav) async {
        final player = MediaKitPlayer(id);
        engines.add(player);
        await player.ready();
        await player.setMpvProperty('ao', 'null');
        await play(player, wav);
        return player;
      }

      // The level in dB that the analysis filter, which comes after the
      // equalizer, measures: the mean of a few readings, as a frame holds a
      // part of a cycle.
      Future<double> level(MediaKitPlayer player) async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final readings = <double>[];
        for (var i = 0; i < 12; i++) {
          final text = await player.getMpvProperty('af-metadata/zviz');
          if (text.contains('lavfi.')) {
            final values = jsonDecode(text) as Map<String, dynamic>;
            readings.add(double.parse('${values['lavfi.astats.1.RMS_level']}'));
          }
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
        expect(readings, isNotEmpty);
        return readings.reduce((a, b) => a + b) / readings.length;
      }

      final tone = File('${dir.path}/tone.wav')..writeAsBytesSync(toneWav());
      final player = await start('equalizer', tone);

      // The equalizer is in the chain, before the levels, and stays there.
      final chain = await player.getMpvProperty('af');
      expect(chain, contains('zeq'));
      expect(chain.indexOf('zeq'), lessThan(chain.indexOf('zviz')));

      final flat = await level(player);

      // Switched off, the gains are kept but the sound is not touched.
      await handler.setEqualizerBandGain(0, 12);
      expect(equalizerBandGains.value, [12, 0, 0, 0, 0]);
      expect(await level(player), closeTo(flat, 0.3));

      // Switched on, the 60 Hz band lifts the 60 Hz tone by about 12 dB.
      await handler.setEqualizerEnabled(true);
      expect(await level(player), closeTo(flat + 12, 0.6));

      // Another band leaves it alone.
      await handler.setEqualizerBandGain(0, 0);
      await handler.setEqualizerBandGain(3, 12);
      expect(await level(player), closeTo(flat, 0.3));

      // A restored backup reaches the engine like a change on the page.
      equalizerBandGains.value = const [12, 0, 0, 0, 0];
      expect(await level(player), closeTo(flat + 12, 0.6));
      await handler.setEqualizerEnabled(false);
      expect(await level(player), closeTo(flat, 0.3));
      await handler.setEqualizerEnabled(true);
      await handler.resetEqualizerBands();
      expect(await level(player), closeTo(flat, 0.3));

      // Live changes never edited the filter chain.
      expect(await player.getMpvProperty('af'), chain);

      // The next engine is prepared with what is saved. 8 kHz audio also
      // proves that a band above its Nyquist frequency leaves the sound be.
      await handler.setEqualizerBandGain(0, 12);
      await handler.setEqualizerBandGain(4, 12);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      engines.remove(player);
      await player.release();
      final low = File('${dir.path}/low.wav')
        ..writeAsBytesSync(toneWav(rate: 8000));
      final replacement = await start('replacement', low);
      expect(await level(replacement), closeTo(flat + 12, 0.6));
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'switched off, the equalizer hands libmpv the samples it was given',
    () async {
      final dir = await prepare();
      final wav = File('${dir.path}/beats.wav')..writeAsBytesSync(beatsWav());

      // What libmpv writes for the song, as 32-bit floats, through [filters].
      Future<Float32List> render(List<String> filters) async {
        JustAudioMediaKit.audioFilters = () => filters;
        final out = File('${dir.path}/${filters.length}.pcm');
        final player = MediaKitPlayer('render${filters.length}');
        await player.ready();
        await player.setMpvProperty('ao', 'pcm');
        await player.setMpvProperty('ao-pcm-file', out.path);
        await player.setMpvProperty('ao-pcm-waveheader', 'no');
        await player.setMpvProperty('audio-format', 'float');
        final done = player.playbackEventMessageStream.firstWhere(
          (event) => event.processingState == ProcessingStateMessage.completed,
        );
        await play(player, wav, loop: false);
        await done.timeout(const Duration(seconds: 10));
        await player.release();
        return Uint8List.fromList(out.readAsBytesSync()).buffer.asFloat32List();
      }

      final plain = await render(const []);
      final through = await render([DesktopEqualizer.filter()]);
      expect(plain, isNotEmpty);
      expect(through.length, plain.length);
      var largest = 0.0;
      for (var i = 0; i < plain.length; i++) {
        largest = [largest, (plain[i] - through[i]).abs()].reduce(max);
      }
      // Rounding in double precision, far below anything a speaker plays.
      expect(largest, lessThan(1e-9));
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
