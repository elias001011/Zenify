import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:just_audio_media_kit/mediakit_player.dart';
import 'package:media_kit/media_kit.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_levels.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/common_services.dart' show userOfflineSongs;
import 'package:musify/services/mix_edits.dart';
import 'package:musify/services/mix_playlists.dart';
import 'package:musify/services/mix_transition.dart';
import 'package:musify/services/settings_manager.dart';

import '../support/app_harness.dart';
import '../support/audio_fixture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  useAppSettings(inMemory: true);
  final library = Platform.environment['MUSIFY_TEST_LIBMPV'];
  test(
    'both native decks follow EQ and hand off after the skipped intro',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      NativePlayer.test = true;
      JustAudioMediaKit.ensureInitialized(libmpv: library);
      final dir = await Directory.systemTemp.createTemp('mix-decks');
      addTearDown(() => dir.delete(recursive: true));
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        paths,
        (_) async => dir.path,
      );
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          paths,
          null,
        ),
      );
      final wav = File('${dir.path}/beats.wav')
        ..writeAsBytesSync(beatsWav(seconds: 24));
      final songs = [
        for (final id in ['first', 'second'])
          {
            'ytid': id,
            'title': id,
            'audioPath': wav.path,
            'duration': 24,
            'sponsorSegments': [
              if (id == 'second') {'start': 0, 'end': 4},
            ],
          },
      ];
      userOfflineSongs.value = songs;
      offlineMode.value = true;
      sponsorBlockSupport.value = true;
      mixPlaylists.value = {'mixed'};
      showPlayerVisualizer.value = false;
      AudioLevels.configureDesktop();
      await mixEdits.set(
        'mixed',
        'first',
        'second',
        const MixEdit(
          outStart: Duration(seconds: 12),
          inStart: Duration.zero,
          length: Duration(seconds: 4),
          style: MixStyle.fade,
        ),
      );
      audioHandler = MusifyAudioHandler();
      addTearDown(() async {
        await audioHandler.stop();
        await audioHandler.audioPlayer.dispose();
      });
      await audioHandler.setVolume(0);
      await audioHandler.playPlaylistSong(
        playlist: {'ytid': 'mixed', 'source': 'user-created', 'list': songs},
        songIndex: 0,
      );
      await audioHandler.seek(const Duration(seconds: 7));
      Future<void> until(Future<bool> Function() ready) async {
        final timer = Stopwatch()..start();
        while (!await ready()) {
          if (timer.elapsed > const Duration(seconds: 6))
            fail('Timed out waiting for the decks');
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      await until(
        () async =>
            MediaKitPlayer.openPlayers.length == 2 &&
            (await MediaKitPlayer.openPlayers.last.getMpvProperty('af'))
                .contains('zmixe'),
      );
      expect(sponsorBlockSupport.value, isTrue);
      expect(await audioHandler.mixSkips(songs.last), [(start: 0, end: 4000)]);
      final standby = MediaKitPlayer.openPlayers.last;
      expect(
        double.tryParse(await standby.getMpvProperty('time-pos')),
        closeTo(4, 0.25),
      );
      await audioHandler.setEqualizerEnabled(true);
      for (final deck in MediaKitPlayer.openPlayers) {
        final filters = await deck.getMpvProperty('af');
        expect(filters, contains('zuser4'));
        expect(filters, contains('zmixl'));
        expect(filters, isNot(contains('zviz')));
      }
      await audioHandler.setEqualizerEnabled(false);
      for (final deck in MediaKitPlayer.openPlayers) {
        expect(await deck.getMpvProperty('af'), isNot(contains('zuser')));
      }
      await audioHandler.seek(const Duration(milliseconds: 12200));
      await until(
        () async =>
            audioHandler.currentQueueIndex == 1 &&
            audioHandler.audioPlayer.playing,
      );
      final incoming = MediaKitPlayer.latest!;
      await until(
        () async =>
            (double.tryParse(await incoming.getMpvProperty('time-pos')) ?? 0) >=
            4,
      );
      expect(audioHandler.mediaItem.value?.extras?['ytid'], 'second');
      await audioHandler.addPlaylistToQueue(
        songs,
        replace: true,
        startIndex: 0,
      );
      final plain = MediaKitPlayer.latest!;
      expect(await plain.getMpvProperty('af'), isEmpty);
    },
    skip: library == null ? 'Set MUSIFY_TEST_LIBMPV' : false,
    timeout: const Timeout(Duration(seconds: 50)),
  );
}
