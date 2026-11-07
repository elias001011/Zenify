import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/settings_manager.dart';

import '../support/audio_fixture.dart';

void main() {
  final library = Platform.environment['MUSIFY_TEST_LIBMPV'];
  const skipReason =
      'Set MUSIFY_TEST_LIBMPV to verify failed songs with native playback';

  /// Builds a queue where every `true` entry is a playable local song and every
  /// `false` entry a local song whose file is gone (offline mode then has no
  /// source to load), starts at song 0 and hands the handler to [body].
  Future<void> withQueue(
    List<bool> playable,
    Future<void> Function(MusifyAudioHandler handler) body,
  ) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    NativePlayer.test = true;
    JustAudioMediaKit.ensureInitialized(libmpv: library);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final directory = await Directory.systemTemp.createTemp(
      'zenify_failed_track_native',
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
    final handler = MusifyAudioHandler();
    await handler.setVolume(0);
    await handler.addPlaylistToQueue([
      for (var i = 0; i < playable.length; i++)
        {
          'ytid': 'local$i',
          'title': 'Track $i',
          'artist': 'Artist',
          'audioPath': playable[i] ? wav.path : '${directory.path}/gone$i.wav',
        },
    ]);
    try {
      await handler.skipToSong(0);
      expect(handler.currentQueueIndex, 0);
      expect(handler.audioPlayer.playing, isTrue);
      await body(handler);
    } finally {
      await handler.stop();
      await handler.audioPlayer.dispose();
    }
  }

  /// The retry waits two seconds per failed song, in real time.
  Future<bool> waitUntil(bool Function() done, {int seconds = 12}) async {
    final deadline = DateTime.now().add(Duration(seconds: seconds));
    while (DateTime.now().isBefore(deadline)) {
      if (done()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return done();
  }

  test(
    'a song that fails to load is skipped and the next song plays',
    () => withQueue([true, false, true, true], (handler) async {
      await handler.skipToNext();
      // The controls fall back to the song that was playing.
      expect(handler.currentQueueIndex, 0);

      final reached = await waitUntil(
        () => handler.currentQueueIndex == 2 && handler.audioPlayer.playing,
      );

      expect(
        handler.currentQueueIndex,
        2,
        reason: 'the broken song 1 must be followed by song 2',
      );
      expect(reached, isTrue);
      expect(handler.audioPlayer.playing, isTrue);
    }),
    skip: library == null ? skipReason : false,
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'two broken songs in a row are both skipped',
    () => withQueue([true, false, false, true], (handler) async {
      await handler.skipToNext();

      final reached = await waitUntil(
        () => handler.currentQueueIndex == 3 && handler.audioPlayer.playing,
      );

      expect(
        handler.currentQueueIndex,
        3,
        reason: 'songs 1 and 2 are broken, song 3 must play',
      );
      expect(reached, isTrue);
      expect(handler.audioPlayer.playing, isTrue);
    }),
    skip: library == null ? skipReason : false,
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'three broken songs in a row stop playback before the good one after them',
    () => withQueue([true, false, false, false, true], (handler) async {
      await handler.skipToNext();

      // Two retries of two seconds each, then the third failure stops.
      final stopped = await waitUntil(
        () =>
            !handler.audioPlayer.playing &&
            handler.audioPlayer.processingState == ProcessingState.idle,
      );
      expect(stopped, isTrue);
      // No further retry is pending once the limit has been reached.
      await Future<void>.delayed(const Duration(seconds: 3));

      // The controls and the queue stay on the song that was playing before
      // the failures, never on a broken one and never on the good one after.
      expect(handler.currentQueueIndex, 0);
      expect(handler.audioPlayer.playing, isFalse);
      expect(handler.audioPlayer.processingState, ProcessingState.idle);
    }),
    skip: library == null ? skipReason : false,
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
