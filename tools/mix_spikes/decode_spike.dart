// Phase 0 proof for the Mix feature: decode a stretch of a song to PCM on
// each platform and estimate its tempo. Not part of the app.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

const _channel = MethodChannel('zenify/audio_decode');

/// Mono 16-bit samples of [length] of [source] (a path or URL) from [start];
/// a negative start counts from the end.
Future<({Int16List samples, int rate})> decodeStretch(
  String source, {
  required Duration start,
  required Duration length,
  required String scratch,
}) async {
  final out = File(scratch);
  if (out.existsSync()) out.deleteSync();
  if (Platform.isAndroid) {
    final rate = await _channel.invokeMethod<int>('decode', {
      'source': source,
      'startMs': start.inMilliseconds,
      'lengthMs': length.inMilliseconds,
      'out': scratch,
    });
    final bytes = await out.readAsBytes();
    return (samples: bytes.buffer.asInt16List(), rate: rate!);
  }

  // Desktop: an mpv of its own writes the stretch to a file, as fast as it
  // decodes, instead of playing it.
  const rate = 11025;
  final player = Player(
    configuration: const PlayerConfiguration(title: 'zenify-decode'),
  );
  final native = player.platform! as NativePlayer;
  for (final MapEntry(:key, :value) in {
    'ao': 'pcm',
    'ao-pcm-file': scratch,
    'ao-pcm-waveheader': 'no',
    'audio-samplerate': '$rate',
    'audio-channels': 'mono',
    'audio-format': 's16',
    'vid': 'no',
    'start': (start.inMilliseconds / 1000).toStringAsFixed(3),
    'length': (length.inMilliseconds / 1000).toStringAsFixed(3),
  }.entries) {
    await native.setProperty(key, value);
  }
  final done = player.stream.completed.firstWhere((completed) => completed);
  await player.open(Media(source));
  await done.timeout(const Duration(seconds: 60));
  await player.dispose();
  final bytes = await out.readAsBytes();
  return (
    samples: bytes.buffer.asInt16List(0, bytes.length ~/ 2),
    rate: rate,
  );
}

/// The tempo of [samples] in beats per minute, between 70 and 180: the lag at
/// which the rises of its loudness best repeat.
double estimateBpm(Int16List samples, int rate) {
  final hop = rate ~/ 100;
  final frames = samples.length ~/ hop;
  final energy = Float64List(frames);
  for (var f = 0; f < frames; f++) {
    var sum = 0.0;
    for (var i = f * hop; i < (f + 1) * hop; i++) {
      sum += samples[i] * samples[i];
    }
    energy[f] = sqrt(sum / hop);
  }
  final onset = Float64List(frames);
  for (var f = 1; f < frames; f++) {
    onset[f] = max(0, energy[f] - energy[f - 1]);
  }
  var best = 0.0;
  var bestLag = 0;
  // 100 frames a second: 180 BPM is a lag of 33 frames, 70 BPM of 86.
  for (var lag = 33; lag <= 86; lag++) {
    var sum = 0.0;
    for (var f = lag; f < frames; f++) {
      sum += onset[f] * onset[f - lag];
    }
    if (sum > best) {
      best = sum;
      bestLag = lag;
    }
  }
  return bestLag == 0 ? 0 : 6000 / bestLag;
}
