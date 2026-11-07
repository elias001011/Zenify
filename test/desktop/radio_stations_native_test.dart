import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:media_kit/media_kit.dart';
import 'package:musify/models/radio_model.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/settings_manager.dart';

import '../support/audio_fixture.dart';

void main() {
  final library = Platform.environment['MUSIFY_TEST_LIBMPV'];
  const skipReason =
      'Set MUSIFY_TEST_LIBMPV to verify radio stations with native playback';

  /// Starts a handler on the native player, with a music queue of two local
  /// songs behind it when [withQueue]: what a radio station is played over.
  Future<void> withHandler(
    Future<void> Function(MusifyAudioHandler handler, List<RadioStation> all)
    body, {
    bool withQueue = false,
    String Function(int index, String wav)? streamUrl,
  }) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    NativePlayer.test = true;
    JustAudioMediaKit.ensureInitialized(libmpv: library);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final directory = await Directory.systemTemp.createTemp(
      'zenify_radio_native',
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
    offlineMode.value = false;
    playNextSongAutomatically.value = false;
    final handler = MusifyAudioHandler();
    await handler.setVolume(0);
    if (withQueue) {
      offlineMode.value = true;
      await handler.addPlaylistToQueue([
        for (var i = 0; i < 2; i++)
          {
            'ytid': 'local$i',
            'title': 'Track $i',
            'artist': 'Artist',
            'audioPath': wav.path,
          },
      ]);
      await handler.skipToSong(0);
      offlineMode.value = false;
      expect(handler.currentQueueIndex, 0);
      expect(handler.hasNext, isTrue);
    }
    final stations = [
      for (var i = 1; i <= 3; i++)
        RadioStation(
          id: 'r$i',
          name: 'Station $i',
          image: '',
          streamUrl: streamUrl?.call(i, wav.path) ?? wav.uri.toString(),
          genre: 'Genre $i',
        ),
    ];
    try {
      await body(handler, stations);
    } finally {
      await handler.stop();
      await handler.audioPlayer.dispose();
    }
  }

  Future<bool> play(
    MusifyAudioHandler handler,
    RadioStation station, [
    List<RadioStation>? list,
  ]) => handler.playRadioStream(
    id: station.id,
    name: station.name,
    streamUrl: station.streamUrl,
    image: station.image,
    genre: station.genre,
    stations: list,
  );

  String? playing(MusifyAudioHandler handler) => handler.mediaItem.value?.id;

  /// The id the native player holds, not just the one the controls show.
  String? loaded(MusifyAudioHandler handler) =>
      (handler.audioPlayer.sequenceState.currentSource?.tag as MediaItem?)?.id;

  test(
    'next and previous switch station in the list and wrap around',
    () => withHandler((handler, all) async {
      expect(await play(handler, all[1], all), isTrue);
      expect(playing(handler), 'r2');
      expect(handler.audioPlayer.playing, isTrue);
      expect(handler.hasNext, isTrue);
      expect(handler.hasPrevious, isTrue);
      expect(handler.canSkipToNext, isTrue);

      await handler.skipToNext();
      expect(playing(handler), 'r3');
      expect(loaded(handler), 'r3');
      expect(handler.audioPlayer.playing, isTrue);

      await handler.skipToNext();
      expect(
        playing(handler),
        'r1',
        reason: 'wraps from the last to the first',
      );
      expect(loaded(handler), 'r1');

      await handler.skipToPrevious();
      expect(
        playing(handler),
        'r3',
        reason: 'wraps from the first to the last',
      );
      expect(loaded(handler), 'r3');
      expect(handler.audioPlayer.playing, isTrue);
    }),
    skip: library == null ? skipReason : false,
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'the notification offers previous and next only when there is a list',
    () => withHandler((handler, all) async {
      await play(handler, all[0], all);
      final withList = handler.playbackState.value.controls;
      expect(withList, contains(MediaControl.skipToPrevious));
      expect(withList, contains(MediaControl.skipToNext));
      expect(withList, isNot(contains(MediaControl.fastForward)));

      await play(handler, all[0]);
      final alone = handler.playbackState.value.controls;
      expect(alone, isNot(contains(MediaControl.skipToPrevious)));
      expect(alone, isNot(contains(MediaControl.skipToNext)));
    }),
    skip: library == null ? skipReason : false,
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'a station started without a list does not skip, nor touch the queue',
    () => withHandler((handler, all) async {
      await play(handler, all[0]);
      expect(playing(handler), 'r1');
      expect(handler.hasNext, isFalse);
      expect(handler.hasPrevious, isFalse);
      expect(handler.canSkipToNext, isFalse);

      await handler.skipToNext();
      await handler.skipToPrevious();

      expect(playing(handler), 'r1');
      expect(loaded(handler), 'r1');
      // The songs that played before the station are left alone.
      expect(handler.currentQueueIndex, 0);
      expect(handler.audioPlayer.playing, isTrue);
    }, withQueue: true),
    skip: library == null ? skipReason : false,
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'a station of a list the queue song also has does not use the queue',
    () => withHandler((handler, all) async {
      await play(handler, all[0], [all[0]]);
      expect(handler.hasNext, isFalse);
      expect(handler.hasPrevious, isFalse);

      await handler.skipToNext();
      await handler.skipToPrevious();

      expect(playing(handler), 'r1');
      expect(handler.currentQueueIndex, 0);
    }, withQueue: true),
    skip: library == null ? skipReason : false,
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'a station that is not in the list it was given has nothing to skip to',
    () => withHandler((handler, all) async {
      await play(handler, all[0], [all[1], all[2]]);
      expect(handler.hasNext, isFalse);

      await handler.skipToNext();

      expect(playing(handler), 'r1');
    }),
    skip: library == null ? skipReason : false,
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'a second skip while the station is still loading is ignored',
    () => withHandler((handler, all) async {
      await play(handler, all[0], all);

      final first = handler.skipToNext();
      final second = handler.skipToNext();
      await Future.wait([first, second]);

      expect(playing(handler), 'r2', reason: 'one step, not two');
      expect(loaded(handler), 'r2');

      // And the next tap, once it has loaded, works again.
      await handler.skipToNext();
      expect(playing(handler), 'r3');
    }),
    skip: library == null ? skipReason : false,
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'a station whose stream ends does not hop to another station or song',
    () => withHandler(
      (handler, all) async {
        await play(handler, all[0], all);
        expect(playing(handler), 'r1');

        // The stream is a fifth of a second long: it ends by itself.
        await Future<void>.delayed(const Duration(seconds: 4));

        expect(playing(handler), 'r1');
        expect(handler.currentQueueIndex, 0);
      },
      withQueue: true,
      streamUrl: (index, wav) {
        final short = File('${File(wav).parent.path}/short.wav')
          ..writeAsBytesSync(silentWav(size: 3200));
        return short.uri.toString();
      },
    ),
    skip: library == null ? skipReason : false,
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'a station that fails to load does not fall back to the old queue',
    () => withHandler(
      (handler, all) async {
        final started = await play(handler, all[1], all);
        expect(started, isFalse);
        expect(playing(handler), 'r2');

        // The player settles again (the user presses play, then pause) and
        // the error of the station is handled; for a song of the queue that
        // is a retry two seconds later on the next one.
        unawaited(handler.audioPlayer.play());
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await handler.audioPlayer.pause();
        await Future<void>.delayed(const Duration(seconds: 5));

        expect(playing(handler), 'r2');
        expect(handler.currentQueueIndex, 0);
        expect(handler.audioPlayer.playing, isFalse);
        // Previous and next are still there to try another station.
        expect(handler.hasNext, isTrue);
      },
      withQueue: true,
      streamUrl: (index, wav) => index == 2
          ? 'file:///zenify/no/such/station.wav'
          : Uri.file(wav).toString(),
    ),
    skip: library == null ? skipReason : false,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
