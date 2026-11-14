// Phase 0 proof for the Mix feature: do two players sound together, and is a
// 50 ms volume ramp smooth? Not part of the app; removed before any merge.
//
// flutter run -t tools/mix_spikes/mix_spike_main.dart
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'decode_spike.dart';
import 'package:path_provider/path_provider.dart';

const _secondHandlesSession = bool.fromEnvironment(
  'SECOND_HANDLES_SESSION',
  defaultValue: true,
);

final _lines = ValueNotifier<List<String>>([]);
final _clock = Stopwatch();

void _log(String message) {
  final line = 'SPIKE ${_clock.elapsedMilliseconds.toString().padLeft(6)} '
      '$message';
  // ignore: avoid_print
  print(line);
  _lines.value = [..._lines.value, line];
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final desktop = Platform.isLinux || Platform.isWindows;
  if (desktop) JustAudioMediaKit.ensureInitialized();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: ValueListenableBuilder(
            valueListenable: _lines,
            builder: (_, lines, _) => ListView(
              reverse: true,
              children: [
                for (final line in lines.reversed)
                  Text(line, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  try {
    await _run(mobile: !desktop);
  } catch (e, stackTrace) {
    _log('FAILED $e\n$stackTrace');
  }
  await _decode();
  _log('DONE');
  if (desktop) exit(0);
}

/// A sine tone as a WAV file: each song of the proof has its own pitch, so a
/// recording tells them apart.
Future<String> _tone(String name, double hertz, int seconds) async {
  const rate = 44100;
  final samples = rate * seconds;
  final data = ByteData(44 + samples * 2);
  void text(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  text(8, 'WAVEfmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    final value = (sin(2 * pi * hertz * i / rate) * 0.5 * 32767).round();
    data.setInt16(44 + i * 2, value, Endian.little);
  }
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name.wav');
  await file.writeAsBytes(data.buffer.asUint8List());
  return file.path;
}

/// Decodes the end and the start of each test song and reads them: how long
/// it took, the tempo, and where the sound ends.
Future<void> _decode() async {
  const sources = String.fromEnvironment(
    'SPIKE_DECODE',
    defaultValue:
        'http://127.0.0.1:8765/click.webm,http://127.0.0.1:8765/click.m4a',
  );
  final dir = await getTemporaryDirectory();
  const stretch = Duration(seconds: 40);
  for (final source in sources.split(',')) {
    for (final (name, start) in [('tail', -stretch), ('head', Duration.zero)]) {
      try {
        final watch = Stopwatch()..start();
        final (:samples, :rate) = await decodeStretch(
          source,
          start: start,
          length: stretch,
          scratch: '${dir.path}/spike_decode.pcm',
        );
        final took = watch.elapsedMilliseconds;
        var lastSound = samples.length - 1;
        while (lastSound > 0 && samples[lastSound].abs() < 300) {
          lastSound--;
        }
        _log(
          'decode ${source.split('/').last} $name: ${took}ms '
          '${(samples.length / rate).toStringAsFixed(1)}s at $rate Hz, '
          'bpm=${estimateBpm(samples, rate).toStringAsFixed(1)}, '
          'sound ends at ${(lastSound / rate).toStringAsFixed(2)}s',
        );
      } catch (e) {
        _log('decode ${source.split('/').last} $name FAILED $e');
      }
    }
  }
}

Future<void> _run({required bool mobile}) async {
  // Songs given from outside (real formats) or the two tones.
  final a =
      Platform.environment['SPIKE_A'] ?? await _tone('spike_a', 440, 16);
  final b =
      Platform.environment['SPIKE_B'] ?? await _tone('spike_b', 1000, 16);

  if (mobile) {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
  }

  // The first player is built as the app builds its own.
  final first = AudioPlayer(
    handleInterruptions: mobile,
    handleAudioSessionActivation: mobile,
  );
  final second = AudioPlayer(
    handleInterruptions: mobile && _secondHandlesSession,
    handleAudioSessionActivation: mobile && _secondHandlesSession,
  );
  _log('secondHandlesSession=$_secondHandlesSession');

  first.playerStateStream.listen(
    (s) => _log('A state playing=${s.playing} ${s.processingState.name}'),
  );
  second.playerStateStream.listen(
    (s) => _log('B state playing=${s.playing} ${s.processingState.name}'),
  );

  _clock.start();
  await first.setAudioSource(AudioSource.file(a));
  unawaited(first.play());
  _log('A play');

  final positions = Timer.periodic(
    const Duration(milliseconds: 500),
    (_) => _log(
      'pos A=${first.position.inMilliseconds} '
      'B=${second.position.inMilliseconds} '
      'vol A=${first.volume.toStringAsFixed(2)} '
      'B=${second.volume.toStringAsFixed(2)}',
    ),
  );

  // The next song is prepared while the first one plays, as the Mix would.
  await Future<void>.delayed(const Duration(seconds: 2));
  final load = Stopwatch()..start();
  await second.setVolume(0);
  await second.setAudioSource(
    AudioSource.file(b),
    initialPosition: const Duration(seconds: 1),
  );
  _log('B loaded in ${load.elapsedMilliseconds} ms, paused');

  await Future<void>.delayed(const Duration(seconds: 2));
  final startedAt = _clock.elapsedMilliseconds;
  final start = second.position;
  unawaited(second.play());
  _log('B play');
  unawaited(() async {
    while (second.position == start) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    _log('B moving after ${_clock.elapsedMilliseconds - startedAt} ms');
  }());

  // Equal-power crossfade over 6 s, one write per 50 ms tick to each player.
  const length = 6000;
  final ramp = Stopwatch()..start();
  var ticks = 0;
  var worstWrite = 0;
  var worstGap = 0;
  var last = 0;
  while (ramp.elapsedMilliseconds < length) {
    final now = ramp.elapsedMilliseconds;
    if (ticks > 0) worstGap = max(worstGap, now - last);
    last = now;
    final t = now / length;
    await Future.wait([
      first.setVolume(cos(t * pi / 2)),
      second.setVolume(sin(t * pi / 2)),
    ]);
    worstWrite = max(worstWrite, ramp.elapsedMilliseconds - now);
    ticks++;
    final rest = 50 - (ramp.elapsedMilliseconds - now);
    if (rest > 0) await Future<void>.delayed(Duration(milliseconds: rest));
  }
  await second.setVolume(1);
  _log(
    'ramp ticks=$ticks worstWrite=${worstWrite}ms worstGap=${worstGap}ms '
    'A.playing=${first.playing} B.playing=${second.playing}',
  );
  await first.stop();
  _log('A stopped');

  // The song that came in must keep playing alone, and pause/resume.
  await Future<void>.delayed(const Duration(seconds: 2));
  await second.pause();
  final pausedAt = second.position;
  await Future<void>.delayed(const Duration(seconds: 1));
  _log('B paused moved=${(second.position - pausedAt).inMilliseconds} ms');
  unawaited(second.play());
  await Future<void>.delayed(const Duration(seconds: 2));
  _log('B resumed at ${second.position.inMilliseconds}');

  positions.cancel();
  await second.stop();
  await first.dispose();
  await second.dispose();
}
