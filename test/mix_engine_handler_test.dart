import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:just_audio/just_audio.dart' as audio;
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/mix_edits.dart';
import 'package:musify/services/mix_engine.dart';
import 'package:musify/services/mix_playlists.dart';
import 'package:musify/services/mix_transition.dart';
import 'package:musify/services/settings_manager.dart';

import 'support/app_harness.dart';

/// A player platform that plays nothing and keeps what the handler asks of
/// each player. just_audio makes a new platform player every time one loads
/// after a stop, so the test tells them apart by the song they loaded. The
/// test decides where each song is, with [emit].
class _Platform extends JustAudioPlatform {
  final players = <_Player>[];
  Duration songLength = const Duration(seconds: 60);
  final failSongs = <String>{};
  final loadBarriers = <String, Completer<void>>{};

  /// The player that last loaded [song].
  _Player of(String song) => players.lastWhere((p) => p.song == song);
  int loads(String song) => players.where((p) => p.song == song).length;
  double lastVolume(String song) => of(song).log.whereType<double>().last;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = _Player(this, request.id);
    players.add(player);
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    players.lastWhere((p) => p.id == request.id).log.add('dispose');
    return DisposePlayerResponse();
  }

  /// A position update from the player of [song], as ExoPlayer or libmpv
  /// would send.
  void emit(
    String song,
    Duration position, {
    ProcessingStateMessage state = ProcessingStateMessage.ready,
  }) => of(song).emit(position, state);
}

class _Player extends AudioPlayerPlatform {
  _Player(this.platform, super.id);

  final _Platform platform;
  final _events = StreamController<PlaybackEventMessage>.broadcast();
  final log = <Object>[];
  String? song;
  Duration? loadedAt;
  int sourceIndex = 0;
  Completer<void>? _playing;

  List<Object> get _log => log;

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
        currentIndex: sourceIndex,
        androidAudioSessionId: null,
      ),
    );
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _log.add('load');
    List<UriAudioSourceMessage> flatten(AudioSourceMessage source) =>
        switch (source) {
          ConcatenatingAudioSourceMessage() =>
            source.children.expand(flatten).toList(),
          ClippingAudioSourceMessage() => [source.child],
          UriAudioSourceMessage() => [source],
          _ => [],
        };
    sourceIndex = request.initialIndex ?? 0;
    final source = flatten(request.audioSourceMessage)[sourceIndex];
    song = Uri.parse(source.uri).pathSegments.last.split('.').first;
    if (platform.failSongs.contains(song)) throw StateError('load failed');
    await platform.loadBarriers[song]?.future;
    loadedAt = request.initialPosition;
    emit(
      request.initialPosition ?? Duration.zero,
      ProcessingStateMessage.ready,
    );
    return LoadResponse(duration: platform.songLength);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    _log.add('play');
    _playing = Completer<void>();
    await _playing!.future;
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    _log.add('pause');
    if (_playing?.isCompleted == false) _playing!.complete();
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    sourceIndex = request.index ?? sourceIndex;
    emit(request.position ?? Duration.zero, ProcessingStateMessage.ready);
    return SeekResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    _log.add(request.volume);
    return SetVolumeResponse();
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    log.add('speed:${request.speed}');
    return SetSpeedResponse();
  }

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async => SetShuffleModeResponse();

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    _log.add('dispose');
    if (_playing?.isCompleted == false) _playing!.complete();
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
    mixTransitions.value = true;
    await Hive.box('settings').delete(MixEditStore.storageKey);
    songFadeSeconds.value = 0;
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
    await Hive.box('userNoBackup').clear();
    audioHandler = handler = MusifyAudioHandler();
    // The player's own clock runs on real time. At a thousandth of the speed
    // it hardly moves, so the positions the test sends decide the song's.
    await handler.audioPlayer.setSpeed(0.001);
    mixPlaylists.value = {'mixed'};
    await handler.addPlaylistToQueue(
      _songs,
      replace: true,
      playlistId: 'mixed',
    );
  });

  tearDown(() async {
    await handler.stop();
    mixTransitions.value = false;
    JustAudioPlatform.instance = previousPlatform;
  });

  /// Lets what a platform event or a call set going finish.
  Future<void> settle() => pumpEventQueue(times: 100);

  /// Lets the Mix's 50 ms timer run a few times.
  Future<void> ticks() async {
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await settle();
  }

  Future<void> startSong(int index) async {
    await handler.skipToSong(index);
    await settle();
    expect(handler.currentQueueIndex, index);
    expect(handler.audioPlayer.playing, isTrue);
  }

  Future<void> at(String song, num seconds) async {
    platform.emit(song, _s(seconds));
    await settle();
  }

  /// Plays the first song up to the moment the second one comes in.
  Future<void> intoTransition() async {
    await startSong(0);
    await at('aaa', 40);
    await at('aaa', 52.5);
  }

  test(
    'cancel preview disposes a stalled active load before restoring playback',
    () async {
      await startSong(2);
      final barrier = platform.loadBarriers['aaa'] = Completer<void>();
      final preview = handler.previewMix(
        _songs[0],
        _songs[1],
        MixCue(
          outStart: _s(52),
          inStart: Duration.zero,
          length: _s(8),
          style: MixStyle.fade,
        ),
      );
      await settle();
      await handler.stopMixPreview().timeout(const Duration(seconds: 2));
      expect(await preview, isTrue);
      expect(handler.mediaItem.value?.extras?['ytid'], 'ccc');
      barrier.complete();
      await settle();
      expect(handler.mediaItem.value?.extras?['ytid'], 'ccc');
      expect(handler.audioPlayer.playing, isTrue);
    },
  );

  test(
    'synced playback preserves the user speed when preview is cancelled',
    () async {
      await mixEdits.set(
        'mixed',
        'aaa',
        'bbb',
        const MixEdit(
          outStart: Duration(seconds: 52),
          inStart: Duration.zero,
          length: Duration(seconds: 8),
          style: MixStyle.blend,
          tempoRatio: 0.96,
        ),
      );
      await intoTransition();
      expect(handler.audioPlayer.speed, closeTo(0.00096, 0.000001));
      final preview = handler.previewMix(
        _songs[0],
        _songs[1],
        MixCue(
          outStart: _s(52),
          inStart: Duration.zero,
          length: _s(8),
          style: MixStyle.fade,
        ),
      );
      await settle();
      await handler.stopMixPreview();
      expect(await preview, isTrue);
      expect(handler.audioPlayer.speed, closeTo(0.001, 0.000001));
    },
  );

  test('with the Mix off there is one player and the song just ends', () async {
    mixTransitions.value = false;
    await startSong(0);
    await at('aaa', 40);
    await at('aaa', 55);
    expect(platform.loads('bbb'), 0);
    expect(handler.currentQueueIndex, 0);
  });

  test('a playlist without the Mix on plays as before', () async {
    mixPlaylists.value = {'another'};
    await startSong(0);
    await at('aaa', 40);
    await at('aaa', 55);
    expect(handler.mixActive, isFalse);
    expect(platform.loads('bbb'), 0);
    expect(handler.mixOutStart.value, isNull);
  });

  test('a queue that replaces the playlist leaves the Mix', () async {
    expect(handler.mixActive, isTrue);
    await handler.addPlaylistToQueue(_songs, replace: true);
    expect(handler.mixActive, isFalse);
  });

  test('the bar is told where the next song comes in', () async {
    await startSong(0);
    expect(handler.mixOutStart.value, isNull);
    await at('aaa', 40);
    expect(handler.mixOutStart.value, _s(52));
    await at('aaa', 52.5);
    expect(handler.mixOutStart.value, isNull, reason: 'a new song plays');
  });

  test('the next song is loaded ahead, silent and paused', () async {
    await startSong(0);
    await at('aaa', 20);
    expect(platform.loads('bbb'), 0, reason: 'too early to load');

    await at('aaa', 40);
    expect(platform.loads('bbb'), 1);
    expect(platform.of('bbb').log, isNot(contains('play')));
    expect(platform.lastVolume('bbb'), 0);
    expect(handler.currentQueueIndex, 0);
    expect(handler.mediaItem.value?.extras?['ytid'], 'aaa');
  });

  test('at the transition the next song is the current one', () async {
    final first = handler.audioPlayer;
    await intoTransition();

    expect(handler.audioPlayer, isNot(same(first)));
    expect(handler.currentQueueIndex, 1);
    expect(handler.mediaItem.value?.extras?['ytid'], 'bbb');
    expect(handler.playbackState.value.playing, isTrue);
    expect(platform.of('bbb').log, contains('play'));
    expect(platform.loads('bbb'), 1, reason: 'played as loaded');
    expect(first.playing, isTrue, reason: 'the one going out still sounds');
  });

  test('the volumes cross with equal power and the tail stops', () async {
    await intoTransition();
    // Half way: the first song at 56 s of 60, the second one 4 s in.
    await at('aaa', 56);
    await at('bbb', 4);
    await ticks();
    final half = mixVolumeFor(cos(pi / 4));
    expect(platform.lastVolume('aaa'), closeTo(half, 0.02));
    expect(platform.lastVolume('bbb'), closeTo(half, 0.02));

    await at('aaa', 59.99);
    await at('bbb', 8);
    await ticks();
    expect(platform.lastVolume('bbb'), 1);
    expect(platform.of('aaa').log.last, 'dispose', reason: 'the tail stopped');
    expect(handler.currentQueueIndex, 1);
    expect(handler.audioPlayer.playing, isTrue);
  });

  test('pause and play reach both songs', () async {
    final first = handler.audioPlayer;
    await intoTransition();
    await handler.pause();
    await settle();
    expect(first.playing, isFalse);
    expect(handler.audioPlayer.playing, isFalse);

    await handler.play();
    await settle();
    expect(first.playing, isTrue);
    expect(handler.audioPlayer.playing, isTrue);
  });

  test('skipping during the transition cuts the tail', () async {
    final first = handler.audioPlayer;
    await intoTransition();
    await handler.skipToNext();
    await settle();
    expect(first.playing, isFalse);
    expect(handler.currentQueueIndex, 2);
    expect(handler.mediaItem.value?.extras?['ytid'], 'ccc');
    expect(platform.lastVolume('ccc'), 1);
  });

  test('seeking in the song that came in cuts the tail', () async {
    final first = handler.audioPlayer;
    await intoTransition();
    await handler.seek(_s(30));
    await settle();
    expect(first.playing, isFalse);
    expect(handler.currentQueueIndex, 1);
    expect(platform.lastVolume('bbb'), 1);
  });

  test('a queue change loads the new next song instead', () async {
    await startSong(0);
    await at('aaa', 40);
    expect(platform.loads('bbb'), 1);

    await handler.removeFromQueue(1);
    await at('aaa', 41);
    expect(platform.of('bbb').log.last, 'dispose');
    expect(platform.loads('ccc'), 1);

    await at('aaa', 52.5);
    expect(handler.mediaItem.value?.extras?['ytid'], 'ccc');
  });

  test('no transition with repeat one or after the last song', () async {
    repeatNotifier.value = AudioServiceRepeatMode.one;
    await startSong(0);
    await at('aaa', 55);
    expect(platform.loads('bbb'), 0);

    repeatNotifier.value = AudioServiceRepeatMode.none;
    await startSong(2);
    await at('ccc', 55);
    expect(platform.loads('bbb'), 0);
    expect(handler.currentQueueIndex, 2);
  });

  test(
    'the song after a transition gets one too, players swapping back',
    () async {
      final first = handler.audioPlayer;
      await intoTransition();
      await at('aaa', 59.99);
      await at('bbb', 8);
      await ticks();

      await at('bbb', 40);
      expect(platform.loads('ccc'), 1);
      await at('bbb', 52.5);
      expect(handler.audioPlayer, same(first));
      expect(handler.currentQueueIndex, 2);
    },
  );

  test(
    'seeking into the transition joins both recordings at the correct gain',
    () async {
      await startSong(0);
      await at('aaa', 40);
      await handler.seek(_s(56));
      await at('aaa', 56);
      await ticks();
      expect(handler.currentQueueIndex, 1);
      expect(handler.audioPlayer.position.inMilliseconds, closeTo(4000, 20));
      expect(
        platform.lastVolume('bbb'),
        closeTo(mixVolumeFor(sin(pi / 4)), 0.02),
      );
    },
  );

  test('a stale load cannot stop the replacement preload', () async {
    await startSong(0);
    final barrier = platform.loadBarriers['bbb'] = Completer<void>();
    await at('aaa', 40);
    await handler.removeFromQueue(1);
    await at('aaa', 41);
    barrier.complete();
    await settle();
    expect(platform.loads('ccc'), 1);
    await at('aaa', 52.5);
    expect(handler.mediaItem.value?.extras?['ytid'], 'ccc');
    expect(handler.audioPlayer.playing, isTrue);
  });

  test(
    'saved pair controls preload position, cue and transition length',
    () async {
      await mixEdits.set(
        'mixed',
        'aaa',
        'bbb',
        const MixEdit(
          outStart: Duration(seconds: 48),
          inStart: Duration(seconds: 3),
          length: Duration(seconds: 4),
          style: MixStyle.fadeOut,
        ),
      );
      await startSong(0);
      await at('aaa', 40);
      expect(handler.mixOutStart.value, _s(48));
      expect(platform.of('bbb').loadedAt, _s(3));
      await at('aaa', 48.5);
      expect(handler.currentQueueIndex, 1);
      await at('bbb', 7);
      await ticks();
      expect(platform.lastVolume('bbb'), 1);
      expect(platform.of('aaa').log.last, 'dispose');
    },
  );

  test('an early manual transition does not wait six seconds', () async {
    platform.songLength = _s(30);
    await mixEdits.set(
      'mixed',
      'aaa',
      'bbb',
      const MixEdit(
        outStart: Duration(seconds: 3),
        inStart: Duration(seconds: 1),
        length: Duration(seconds: 2),
        style: MixStyle.smooth,
      ),
    );
    await startSong(0);
    await at('aaa', 1);
    expect(platform.loads('bbb'), 1);
    await at('aaa', 3.2);
    expect(handler.currentQueueIndex, 1);
  });

  test('saving after a preload discards the old automatic cue', () async {
    await startSong(0);
    await at('aaa', 40);
    expect(platform.of('bbb').loadedAt, Duration.zero);
    await mixEdits.set(
      'mixed',
      'aaa',
      'bbb',
      const MixEdit(
        outStart: Duration(seconds: 49),
        inStart: Duration(seconds: 5),
        length: Duration(seconds: 3),
        style: MixStyle.smooth,
      ),
    );
    handler.refreshMix();
    await settle();
    expect(handler.mixOutStart.value, _s(49));
    expect(platform.of('bbb').loadedAt, _s(5));
  });

  test(
    'speed changes reach the prepared deck and both songs during a fade',
    () async {
      await startSong(0);
      await at('aaa', 40);
      await handler.setSpeed(0.002);
      expect(platform.of('aaa').log, contains('speed:0.002'));
      expect(platform.of('bbb').log, contains('speed:0.002'));
      await at('aaa', 52.5);
      expect(handler.audioPlayer.speed, 0.002);
      await handler.setSpeed(0.003);
      expect(platform.of('aaa').log.last, 'speed:0.003');
      expect(platform.of('bbb').log.last, 'speed:0.003');
    },
  );

  test('a single SponsorBlock clip is ineligible for a transition', () async {
    await startSong(0);
    await handler.audioPlayer.setAudioSource(
      audio.ClippingAudioSource(
        child: audio.AudioSource.uri(Uri.parse('http://127.0.0.1/aaa.mp3')),
        start: _s(10),
        tag: handler.mediaItem.value,
      ),
    );
    await at('aaa', 40);
    await at('aaa', 52.5);
    expect(handler.mixOutStart.value, isNull);
    expect(platform.loads('bbb'), 0);
    expect(handler.currentQueueIndex, 0);
  });

  test(
    'preview restores the clip index and repeat mode after a deck swap',
    () async {
      await startSong(2);
      final tag = handler.mediaItem.value;
      final uri = Uri.parse('http://127.0.0.1/ccc.mp3');
      await handler.audioPlayer.setAudioSource(
        // ignore: deprecated_member_use
        audio.ConcatenatingAudioSource(
          children: [
            audio.ClippingAudioSource(
              child: audio.AudioSource.uri(uri),
              start: Duration.zero,
              end: _s(10),
              tag: tag,
            ),
            audio.ClippingAudioSource(
              child: audio.AudioSource.uri(uri),
              start: _s(20),
              end: _s(40),
              tag: tag,
            ),
          ],
        ),
        initialIndex: 1,
        initialPosition: _s(7),
      );
      await handler.audioPlayer.setLoopMode(audio.LoopMode.one);
      await handler.pause();
      final preview = handler.previewMix(
        _songs[0],
        _songs[1],
        MixCue(
          outStart: _s(52),
          inStart: Duration.zero,
          length: _s(8),
          style: MixStyle.smooth,
        ),
      );
      await settle();
      await at('aaa', 52.5);
      await handler.stopMixPreview();
      expect(await preview, isTrue);
      expect(handler.audioPlayer.currentIndex, 1);
      expect(handler.audioPlayer.position.inMilliseconds, 7000);
      expect(handler.audioPlayer.loopMode, audio.LoopMode.one);
      expect(handler.audioPlayer.playing, isFalse);
    },
  );

  test('preview uses the decks and restores a paused song without changing the queue', () async {
    await startSong(2);
    await handler.pause();
    await handler.seek(_s(17));
    final entries = handler.queue.value.map((s) => s.id).toList();
    final preview = handler.previewMix(
      _songs[0],
      _songs[1],
      MixCue(
        outStart: _s(52),
        inStart: _s(2),
        length: _s(8),
        style: MixStyle.smooth,
      ),
    );
    await settle();
    expect(platform.of('aaa').loadedAt, _s(47));
    await at('aaa', 52.5);
    expect(handler.currentQueueIndex, 2);
    expect(handler.mediaItem.value?.extras?['ytid'], 'bbb');
    expect(handler.queue.value.map((s) => s.id).toList(), entries);
    await at('bbb', 10);
    await ticks();
    expect(await preview, isTrue);
    expect(handler.mediaItem.value?.extras?['ytid'], 'ccc');
    expect(handler.currentQueueIndex, 2);
    expect(platform.of('ccc').loadedAt, _s(17));
    expect(handler.audioPlayer.playing, isFalse);
    expect(handler.audioPlayer.speed, 0.001);
  });

  test('cancelled preview restores playback and stop still stops it', () async {
    await startSong(2);
    final preview = handler.previewMix(
      _songs[0],
      _songs[1],
      MixCue(
        outStart: _s(52),
        inStart: Duration.zero,
        length: _s(8),
        style: MixStyle.wave,
      ),
    );
    await settle();
    await handler.stopMixPreview();
    expect(await preview, isTrue);
    expect(handler.currentQueueIndex, 2);
    expect(handler.audioPlayer.playing, isTrue);
    final again = handler.previewMix(
      _songs[0],
      _songs[1],
      MixCue(
        outStart: _s(52),
        inStart: Duration.zero,
        length: _s(8),
        style: MixStyle.wave,
      ),
    );
    await settle();
    await handler.stop();
    await again;
    expect(handler.audioPlayer.playing, isFalse);
  });

  test(
    'preview failure restores playback without skipping or changing the queue',
    () async {
      await startSong(2);
      platform.failSongs.add('bbb');
      expect(
        await handler.previewMix(
          _songs[0],
          _songs[1],
          MixCue(
            outStart: _s(52),
            inStart: Duration.zero,
            length: _s(8),
            style: MixStyle.smooth,
          ),
        ),
        isFalse,
      );
      expect(handler.currentQueueIndex, 2);
      expect(handler.mediaItem.value?.extras?['ytid'], 'ccc');
      expect(handler.audioPlayer.playing, isTrue);
    },
  );
}
