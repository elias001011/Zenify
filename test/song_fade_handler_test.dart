import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/queue_persistence_service.dart';
import 'package:musify/services/settings_manager.dart';

import 'support/app_harness.dart';

/// A player platform that plays nothing and keeps a log of what the handler
/// asks of it. The test decides where the song is, with [emit].
class _Platform extends JustAudioPlatform {
  /// Every volume the handler sent to a player and every play request, in
  /// order, across the players it created.
  final log = <Object>[];
  _Player? current;
  Duration songLength = const Duration(seconds: 60);

  List<double> get volumes => log.whereType<double>().toList();
  double get lastVolume => volumes.last;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      current = _Player(this, request.id);

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async => DisposePlayerResponse();

  /// A position update from the player, as ExoPlayer or libmpv would send.
  void emit(
    Duration position, {
    ProcessingStateMessage state = ProcessingStateMessage.ready,
  }) => current!.emit(position, state);
}

class _Player extends AudioPlayerPlatform {
  _Player(this.platform, super.id);

  final _Platform platform;
  final _events = StreamController<PlaybackEventMessage>.broadcast();
  Completer<void>? _playing;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  void emit(Duration position, ProcessingStateMessage state) {
    _events.add(
      PlaybackEventMessage(
        processingState: state,
        updateTime: DateTime.now(),
        updatePosition: position,
        bufferedPosition: platform.songLength,
        duration: platform.songLength,
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
      ),
    );
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    emit(
      request.initialPosition ?? Duration.zero,
      ProcessingStateMessage.ready,
    );
    return LoadResponse(duration: platform.songLength);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    platform.log.add('play');
    _playing = Completer<void>();
    await _playing!.future;
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    _playing?.complete();
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    emit(request.position ?? Duration.zero, ProcessingStateMessage.ready);
    return SeekResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    platform.log.add(request.volume);
    return SetVolumeResponse();
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async => SetShuffleModeResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    _playing?.complete();
    return DisposeResponse();
  }
}

Duration _s(num seconds) => Duration(microseconds: (seconds * 1e6).round());

final _songs = [
  for (final id in ['aaa', 'bbb', 'ccc'])
    {'ytid': id, 'title': 'Song $id', 'artist': 'Artist', 'duration': 60},
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppSettings(inMemory: true);

  late _Platform platform;
  late MusifyAudioHandler handler;
  late JustAudioPlatform previousPlatform;

  setUp(() async {
    // The desktop player: the phone's would reach for audio session plugins.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    previousPlatform = JustAudioPlatform.instance;
    platform = _Platform();
    JustAudioPlatform.instance = platform;
    songFadeSeconds.value = 6;
    repeatNotifier.value = AudioServiceRepeatMode.none;
    shuffleNotifier.value = false;
    offlineMode.value = false;
    playNextSongAutomatically.value = false;
    wrappedEnabled.value = false;
    sponsorBlockSupport.value = false;
    for (final song in _songs) {
      await addOrUpdateData<String>(
        'cache',
        'song_${song['ytid']}_${audioQualitySetting.value}_url',
        'http://127.0.0.1/${song['ytid']}.mp3',
      );
    }
    // A new handler restores the queue the last one saved.
    await Hive.box('userNoBackup').clear();
    audioHandler = handler = MusifyAudioHandler();
    // The player's own clock runs on real time. At a thousandth of the speed
    // it hardly moves, so the positions the test sends decide the song's.
    await handler.audioPlayer.setSpeed(0.001);
    await handler.addPlaylistToQueue(_songs);
  });

  tearDown(() async {
    await handler.cancelSleepTimer();
    await handler.stop();
    await handler.audioPlayer.dispose();
    JustAudioPlatform.instance = previousPlatform;
  });

  /// Lets what a platform event or a call set going finish.
  Future<void> settle() => pumpEventQueue(times: 100);

  Future<void> startSong(int index) async {
    await handler.skipToSong(index);
    await settle();
    expect(handler.currentQueueIndex, index);
    expect(handler.audioPlayer.playing, isTrue);
  }

  Future<void> at(num seconds) async {
    platform.emit(_s(seconds));
    await settle();
  }

  /// The gain of the fade the volume sent to the player should have at
  /// [seconds] into a song, for a song with [fadeIn] and [fadeOut].
  double gainAt(num seconds, {bool fadeIn = false, bool fadeOut = true}) {
    const length = 6;
    var gain = 1.0;
    if (fadeIn && seconds < length) gain *= sin(seconds / length * pi / 2);
    final into = seconds - (60 - length);
    if (fadeOut && into > 0) gain *= cos(into / length * pi / 2);
    return gain;
  }

  group('the fade out', () {
    test('starts in the last seconds of a song another one follows', () async {
      await startSong(0);
      expect(platform.lastVolume, 1);

      await at(30);
      expect(platform.lastVolume, 1);
      await at(54);
      expect(platform.lastVolume, closeTo(1, 0.001));
      await at(57);
      expect(platform.lastVolume, closeTo(gainAt(57), 0.01));
      expect(platform.lastVolume, closeTo(sqrt(0.5), 0.01));
      await at(59.4);
      expect(platform.lastVolume, closeTo(gainAt(59.4), 0.01));
      await at(60);
      expect(platform.lastVolume, closeTo(0, 0.001));
    });

    test('steps the volume between the position updates', () async {
      // The player's own clock and the timer that follows it run on real time
      // (fake time would not move the position), for about a second here.
      platform.songLength = const Duration(minutes: 4);
      await handler.audioPlayer.setSpeed(1);
      await startSong(0);

      // Out of a fade zone nothing is written, however long the song plays.
      await at(100);
      var mark = platform.log.length;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(platform.log.length, mark);

      // In it the position updates come every 200 ms at most; the volume
      // still follows the player's clock about every 50 ms.
      await at(236);
      mark = platform.log.length;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final steps = platform.log.skip(mark).whereType<double>().toList();
      expect(steps.length, greaterThanOrEqualTo(6));
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i], lessThan(steps[i - 1]));
      }

      // And a pause ends it.
      await handler.pause();
      await settle();
      mark = platform.log.length;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(platform.log.length, mark);
    });

    test('is not there for the last song of the queue', () async {
      await startSong(2);
      await at(57);
      await at(59.5);
      expect(platform.volumes.every((v) => v == 1), isTrue);
    });

    test('is there for the last song when the queue repeats', () async {
      await handler.setRepeatMode(AudioServiceRepeatMode.all);
      await startSong(2);
      await at(57);
      expect(platform.lastVolume, closeTo(sqrt(0.5), 0.01));
    });

    test('is not there when the song repeats', () async {
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      await startSong(0);
      await at(57);
      await at(59.5);
      expect(platform.volumes.every((v) => v == 1), isTrue);
    });

    test('is not there when the sleep timer stops at the end of it', () async {
      await handler.setSleepTimerEndOfSong();
      await startSong(0);
      await at(57);
      await at(59.5);
      expect(platform.volumes.every((v) => v == 1), isTrue);
    });

    test('is not there for a radio station', () async {
      final played = await handler.playRadioStream(
        id: 'radio',
        name: 'Radio',
        streamUrl: 'http://127.0.0.1/radio.mp3',
        image: '',
      );
      await settle();
      expect(played, isTrue);
      await at(57);
      await at(59.5);
      expect(platform.volumes.every((v) => v == 1), isTrue);
    });

    test('is not there when the fade is off', () async {
      songFadeSeconds.value = 0;
      await startSong(0);
      await at(57);
      await at(59.5);
      expect(platform.volumes.every((v) => v == 1), isTrue);
    });

    test('gives back the volume when the song is sought out of it', () async {
      await startSong(0);
      await at(58);
      expect(platform.lastVolume, lessThan(0.6));
      await handler.seek(_s(20));
      await settle();
      expect(platform.lastVolume, 1);
    });

    test('goes on from where it was after a pause', () async {
      await startSong(0);
      await at(57);
      final paused = platform.lastVolume;
      await handler.pause();
      await settle();
      // Nothing jumps while it is paused.
      expect(platform.lastVolume, closeTo(paused, 0.001));

      await handler.play();
      await settle();
      expect(platform.lastVolume, closeTo(paused, 0.01));
      await at(58.5);
      expect(platform.lastVolume, closeTo(gainAt(58.5), 0.01));
    });

    test(
      'is dropped when the fade is turned off in the middle of it',
      () async {
        await startSong(0);
        await at(58);
        expect(platform.lastVolume, lessThan(0.6));
        songFadeSeconds.value = 0;
        await at(58.1);
        expect(platform.lastVolume, 1);
      },
    );
  });

  group('the fade in', () {
    /// Finishes the playing song, as the player does at its end.
    Future<void> finish() async {
      platform.emit(
        platform.songLength,
        state: ProcessingStateMessage.completed,
      );
      await settle();
    }

    test('starts the next song silent and raises it, with no blip', () async {
      await startSong(0);
      await at(57);
      final before = platform.log.length;
      await finish();
      expect(handler.currentQueueIndex, 1);
      expect(handler.audioPlayer.playing, isTrue);

      // After the end of the first song: the next one's volume is set to
      // silence before the play request, and nothing louder comes first.
      final after = platform.log.skip(before).toList();
      final play = after.indexOf('play');
      expect(play, isNonNegative);
      final beforePlay = after.take(play).whereType<double>().toList();
      expect(beforePlay, isNotEmpty);
      expect(beforePlay.last, closeTo(0, 0.001));
      expect(beforePlay.every((v) => v < 0.001), isTrue);

      await at(1.5);
      expect(platform.lastVolume, closeTo(gainAt(1.5, fadeIn: true), 0.01));
      await at(3);
      expect(platform.lastVolume, closeTo(sqrt(0.5), 0.01));
      await at(6);
      expect(platform.lastVolume, 1);
    });

    test('is not repeated when the song is sought back to its start', () async {
      await startSong(0);
      await finish();
      await at(7);
      expect(platform.lastVolume, 1);
      await handler.seek(_s(1));
      await settle();
      expect(platform.lastVolume, 1);
    });

    test('is not there when the fade is off', () async {
      songFadeSeconds.value = 0;
      await startSong(0);
      await finish();
      expect(handler.currentQueueIndex, 1);
      expect(platform.volumes.every((v) => v == 1), isTrue);
    });

    test(
      'is not there for a song skipped to in the middle of a fade',
      () async {
        await startSong(0);
        await at(58.5);
        expect(platform.lastVolume, lessThan(0.5));
        final before = platform.log.length;
        await handler.skipToNext();
        await settle();
        expect(handler.currentQueueIndex, 1);
        // Until the next song plays, nothing but its full volume is sent.
        final after = platform.log.skip(before).toList();
        expect(after.whereType<double>().every((v) => v == 1), isTrue);
        expect(after, contains('play'));
        expect(platform.lastVolume, 1);
      },
    );

    test('is not there for a song the user skips to', () async {
      await startSong(0);
      await at(30);
      await handler.skipToNext();
      await settle();
      expect(handler.currentQueueIndex, 1);
      expect(platform.volumes.every((v) => v == 1), isTrue);

      await handler.skipToQueueItem(2);
      await settle();
      expect(handler.currentQueueIndex, 2);
      expect(platform.volumes.every((v) => v == 1), isTrue);

      await handler.skipToPrevious();
      await settle();
      expect(handler.currentQueueIndex, 1);
      expect(platform.volumes.every((v) => v == 1), isTrue);
    });

    test('is not there for a song picked after the queue ended', () async {
      await startSong(2);
      await finish();
      await startSong(0);
      await at(1);
      expect(platform.volumes.every((v) => v == 1), isTrue);
    });

    test('is not there when play starts a queue nothing played from', () async {
      // As after a restore: play() loads the song the queue stopped at.
      await handler.play();
      await settle();
      expect(handler.audioPlayer.playing, isTrue);
      await at(1);
      expect(platform.volumes.every((v) => v == 1), isTrue);
    });

    test('is not there on resuming after a pause', () async {
      await startSong(0);
      await at(20);
      await handler.pause();
      await handler.play();
      await settle();
      expect(platform.volumes.every((v) => v == 1), isTrue);
    });

    test('is not there when the song repeats', () async {
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      await startSong(0);
      await finish();
      expect(handler.currentQueueIndex, 0);
      expect(platform.volumes.every((v) => v == 1), isTrue);
    });
  });

  group('the volume', () {
    test(
      'the handler keeps the volume the user chose through a fade',
      () async {
        final shown = <double>[];
        final subscription = handler.volumeStream.listen(shown.add);
        addTearDown(subscription.cancel);
        await handler.setVolume(0.8);
        await startSong(0);
        expect(platform.lastVolume, 0.8);

        await at(57);
        expect(handler.volume, 0.8);
        expect(platform.lastVolume, closeTo(0.8 * gainAt(57), 0.01));
        await at(59);
        expect(handler.volume, 0.8);
        expect(platform.lastVolume, closeTo(0.8 * gainAt(59), 0.01));

        // The volume control only ever hears of the user's volume.
        await settle();
        expect(shown, [1, 0.8]);
      },
    );

    test('a volume chosen during a fade follows the fade', () async {
      await startSong(0);
      await at(57);
      await handler.setVolume(0.5);
      expect(handler.volume, 0.5);
      expect(platform.lastVolume, closeTo(0.5 * gainAt(57), 0.01));

      await at(58.5);
      expect(platform.lastVolume, closeTo(0.5 * gainAt(58.5), 0.01));
      await handler.setVolume(1);
      expect(platform.lastVolume, closeTo(gainAt(58.5), 0.01));
    });

    test('mute and unmute work during a fade', () async {
      await handler.setVolume(0.8);
      await startSong(0);
      await at(57);

      await handler.toggleMute();
      expect(handler.volume, 0);
      expect(platform.lastVolume, 0);
      // The fade goes on under the mute.
      await at(58);
      expect(handler.volume, 0);
      expect(platform.lastVolume, 0);

      await handler.toggleMute();
      expect(handler.volume, 0.8);
      expect(platform.lastVolume, closeTo(0.8 * gainAt(58), 0.01));
    });

    test('the user volume is applied to a fading in song', () async {
      await handler.setVolume(0.5);
      await startSong(0);
      platform.emit(
        platform.songLength,
        state: ProcessingStateMessage.completed,
      );
      await settle();
      expect(handler.currentQueueIndex, 1);
      await at(3);
      expect(platform.lastVolume, closeTo(0.5 * sqrt(0.5), 0.01));
      expect(handler.volume, 0.5);
    });
  });

  group('the sleep timer', () {
    /// The sleep timer counts on a stopwatch, which fake time does not move:
    /// this waits for it in real time, for a few hundred milliseconds.
    Future<void> waitForExpiry() async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (sleepTimerNotifier.value != null &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await settle();
    }

    test(
      'fades to silence over a fading song and gives back the volume',
      () async {
        await handler.setVolume(0.8);
        await startSong(0);
        await at(57);
        final songGain = gainAt(57);
        expect(platform.lastVolume, closeTo(0.8 * songGain, 0.01));

        final mark = platform.log.length;
        await handler.setSleepTimer(const Duration(milliseconds: 400));
        await waitForExpiry();

        final during = platform.log.skip(mark).whereType<double>().toList();
        // It faded down, below what the song's fade alone sends, to silence.
        expect(
          during.any((v) => v > 0.01 && v < 0.8 * songGain - 0.05),
          isTrue,
        );
        expect(during.any((v) => v < 0.001), isTrue);
        expect(handler.audioPlayer.playing, isFalse);

        // And the volume the user chose is back. The stopped player keeps it
        // for when it plays again, times the fade of the song it stopped in.
        expect(handler.volume, 0.8);
        expect(handler.audioPlayer.volume, closeTo(0.8 * songGain, 0.01));
      },
    );
  });

  test(
    'a restored song keeps its saved spot, moved or not, while it loads',
    () async {
      await handler.stop();
      await handler.audioPlayer.dispose();
      final memory = QueuePersistenceService()
        ..saveQueue(
          [
            for (final (i, song) in _songs.indexed)
              {...song, 'queueEntryId': '$i'},
          ],
          [],
          1,
        )
        ..savePosition('1', _s(30));
      await memory.flush();
      audioHandler = handler = MusifyAudioHandler();
      await settle();

      final positions = <Duration>[];
      final subscription = handler.positionDataStream.listen(
        (data) => positions.add(data.position),
      );
      await settle();
      expect(positions, [_s(30)]);
      await handler.seek(_s(45));
      await settle();
      expect(positions, [_s(30), _s(45)]);
      await handler.play();
      await settle();
      await subscription.cancel();

      expect(positions.skip(1), everyElement(_s(45)));
    },
  );
}
