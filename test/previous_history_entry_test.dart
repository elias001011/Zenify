import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/data_manager.dart';
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

  test(
    'previous from the history gives the song a new queue entry id',
    () async {
      await startSong(0);
      await at(60);
      platform.emit(_s(60), state: ProcessingStateMessage.completed);
      await settle();
      await handler.skipToPrevious();
      await settle();
      await handler.skipToPrevious();
      await settle();
      final ids = [for (final s in handler.queue.value) s.id];
      expect(
        ids.toSet().length,
        ids.length,
        reason: 'duplicate queue entry ids',
      );
    },
  );
}
