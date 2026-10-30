import 'package:audio_service/audio_service.dart';
import 'package:musify/services/audio_service.dart';

class WaveTestHandler extends BaseAudioHandler implements MusifyAudioHandler {
  void ready() => playbackState.add(
    PlaybackState(playing: true, processingState: AudioProcessingState.ready),
  );

  @override
  Future<void> skipToNext({bool playWhenReady = true}) async {}
  @override
  Future<void> skipToPrevious({bool playWhenReady = true}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
