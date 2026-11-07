import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/playback_buffer.dart';
import 'package:musify/services/settings_manager.dart' show bufferWholeSong;

import 'support/app_harness.dart';

/// Records what the player is created with and loads nothing.
class _RecordingPlatform extends JustAudioPlatform {
  InitRequest? request;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    this.request = request;
    return _SilentPlayer(request.id);
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async => DisposePlayerResponse();
}

class _SilentPlayer extends AudioPlayerPlatform {
  _SilentPlayer(super.id);

  final _events = StreamController<PlaybackEventMessage>.broadcast();

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _events.add(
      PlaybackEventMessage(
        processingState: ProcessingStateMessage.ready,
        updateTime: DateTime.now(),
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        duration: null,
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
      ),
    );
    return LoadResponse(duration: null);
  }

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
    SetAndroidAudioAttributesRequest request,
  ) async => SetAndroidAudioAttributesResponse();

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

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
  Future<DisposeResponse> dispose(DisposeRequest request) async =>
      DisposeResponse();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppSettings(inMemory: true);

  test('with the setting on, Android loads a whole song ahead', () {
    final control = wholeSongLoadConfiguration.androidLoadControl!;

    // ExoPlayer loads until the max and resumes under the min: equal values
    // at ten minutes keep a whole song loaded.
    expect(control.minBufferDuration, const Duration(minutes: 10));
    expect(control.maxBufferDuration, const Duration(minutes: 10));
    // The start of a song stays fast.
    expect(
      control.bufferForPlaybackDuration,
      const Duration(milliseconds: 500),
    );
    expect(
      control.bufferForPlaybackAfterRebufferDuration,
      const Duration(seconds: 8),
    );
    // Ten minutes of a 256 kbps stream (18 MiB) fit under the memory limit,
    // which stays a limit: time does not override it.
    expect(control.targetBufferBytes, 32 * 1024 * 1024);
    expect(control.prioritizeTimeOverSizeThresholds, isFalse);
    // ExoPlayer requires min <= max and both at least the playback waits.
    expect(control.minBufferDuration <= control.maxBufferDuration, isTrue);
    expect(
      control.minBufferDuration >=
          control.bufferForPlaybackAfterRebufferDuration,
      isTrue,
    );
  });

  test('with the setting off, Android keeps the Musify buffer', () {
    expect(bufferWholeSong.value, isFalse);
    final control = playbackLoadConfigurationFor(wholeSong: false)
        .androidLoadControl!;
    expect(control.maxBufferDuration, const Duration(seconds: 60));
    expect(control.minBufferDuration, const Duration(seconds: 50));
    expect(
      control.bufferForPlaybackAfterRebufferDuration,
      const Duration(seconds: 3),
    );
    expect(control.targetBufferBytes, isNull);
  });

  for (final wholeSong in [false, true]) {
    test(
      'the audio handler creates its player with the setting $wholeSong',
      () async {
        bufferWholeSong.value = wholeSong;
        addTearDown(() => bufferWholeSong.value = false);
        final platform = _RecordingPlatform();
        final previous = JustAudioPlatform.instance;
        JustAudioPlatform.instance = platform;
        addTearDown(() => JustAudioPlatform.instance = previous);
        audioHandler = MusifyAudioHandler();
        addTearDown(audioHandler.audioPlayer.dispose);

        // The platform player is created with the first source.
        await audioHandler.audioPlayer.setAudioSource(
          AudioSource.uri(Uri.parse('http://127.0.0.1/song.mp3')),
        );

        final sent =
            platform.request!.audioLoadConfiguration!.androidLoadControl!;
        final expected = playbackLoadConfigurationFor(wholeSong: wholeSong)
            .androidLoadControl!;
        expect(sent.minBufferDuration, expected.minBufferDuration);
        expect(sent.maxBufferDuration, expected.maxBufferDuration);
        expect(
          sent.bufferForPlaybackDuration,
          expected.bufferForPlaybackDuration,
        );
        expect(
          sent.bufferForPlaybackAfterRebufferDuration,
          expected.bufferForPlaybackAfterRebufferDuration,
        );
        expect(sent.targetBufferBytes, expected.targetBufferBytes);
        expect(
          sent.prioritizeTimeOverSizeThresholds,
          expected.prioritizeTimeOverSizeThresholds,
        );
        expect(sent.backBufferDuration, expected.backBufferDuration);
        expect(
          sent.maxBufferDuration,
          wholeSong ? const Duration(minutes: 10) : const Duration(seconds: 60),
        );
      },
    );
  }
}
