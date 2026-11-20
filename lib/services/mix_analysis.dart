/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     Musify is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Musify is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Musify, including how to contribute,
 *     please visit: https://github.com/gokadzev/Musify
 */

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:media_kit/media_kit.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/mix_harmony.dart';
import 'package:musify/services/mix_transition.dart';
import 'package:musify/utilities/platform_utils.dart';
import 'package:path_provider/path_provider.dart';

/// What the analysis found at one end of a song: its start (head) or its
/// end (tail). Times are milliseconds into the song.
class MixEdge {
  const MixEdge({
    required this.sound,
    required this.bpm,
    required this.beat,
    required this.beatAt,
    required this.level,
    required this.soft,
    this.key,
    this.keyConfidence = 0,
    this.bar = 0,
  });

  factory MixEdge.fromList(List<dynamic> values) => MixEdge(
    sound: (values[0] as num).toInt(),
    bpm: (values[1] as num).toDouble(),
    beat: (values[2] as num).toDouble(),
    beatAt: (values[3] as num).toInt(),
    level: (values[4] as num).toDouble(),
    soft: (values[5] as num).toInt(),
    key: values.length > 6 && values[6] != -1 ? values[6].toInt() : null,
    keyConfidence: values.length > 7 ? values[7].toDouble() : 0,
    bar: values.length > 8 ? (values[8] as num).toInt() : 0,
  );

  /// Where the sound starts (head) or ends (tail).
  final int sound;

  /// The tempo, in beats per minute.
  final double bpm;

  /// How steady the beat is, from 0 (none) to 1 (a metronome).
  final double beat;

  /// The time of one beat.
  final int beatAt;

  /// How loud the song is next to this end, from 0 to 1.
  final double level;

  /// How long the song takes to come up (head) or to die away (tail).
  final int soft;
  final int? key;
  final double keyConfidence;

  /// Which beat of four (counted from [beatAt]) starts a bar: a guess from
  /// where the loudness rises most.
  final int bar;
  String? get camelot => key == null ? null : camelotKey(key!);

  /// Whether the song has a beat a transition can follow.
  bool get rhythmic => beat >= MixAnalyzer.steadyBeat && bpm > 0;

  List<num> toList() => [
    sound,
    bpm,
    beat,
    beatAt,
    level,
    soft,
    key ?? -1,
    keyConfidence,
    bar,
  ];
}

/// Reads one end of a song from its [samples] (mono, [rate] a second), which
/// start [offset] milliseconds into it.
MixEdge analyzeEdge(
  Int16List samples,
  int rate, {
  required int offset,
  required bool tail,
}) {
  // Loudness of every hundredth of a second.
  final hop = max(1, rate ~/ 100);
  final frames = samples.length ~/ hop;
  final loud = Float64List(frames);
  var peak = 0.0;
  // Each over 40 ms with soft edges: a bass note must not ripple like a beat.
  final window = Float64List(hop * 4);
  for (var i = 0; i < window.length; i++) {
    window[i] = 0.5 - 0.5 * cos(2 * pi * (i + 0.5) / window.length);
  }
  for (var f = 0; f < frames; f++) {
    var sum = 0.0;
    var weight = 0.0;
    final start = f * hop - hop * 3 ~/ 2;
    for (var i = 0; i < window.length; i++) {
      final at = start + i;
      if (at < 0 || at >= samples.length) continue;
      sum += window[i] * samples[at] * samples[at];
      weight += window[i];
    }
    loud[f] = sqrt(sum / weight) / 32768;
    if (loud[f] > peak) peak = loud[f];
  }
  // A frame is close to 10 ms, not exactly: 40 s of the difference is a beat off.
  final frameMs = hop * 1000 / rate;
  int time(num frame) => offset + (frame * frameMs).round();
  if (frames < 200 || peak < 0.002) {
    return MixEdge(
      sound: tail ? time(frames) : offset,
      bpm: 0,
      beat: 0,
      beatAt: offset,
      level: 0,
      soft: 0,
    );
  }

  // Where the sound is: from the first to the last frame above silence.
  final silence = max(0.003, peak * 0.02);
  var first = 0;
  while (first < frames - 1 && loud[first] < silence) {
    first++;
  }
  var last = frames - 1;
  while (last > first && loud[last] < silence) {
    last--;
  }

  // The usual loudness, and half a second's average at each frame.
  final sorted = Float64List.fromList(loud.sublist(first, last + 1))..sort();
  final usual = sorted[sorted.length ~/ 2];
  double around(int frame) {
    final from = max(first, frame - 25);
    final to = min(last, frame + 25);
    var sum = 0.0;
    for (var f = from; f <= to; f++) {
      sum += loud[f];
    }
    return sum / (to - from + 1);
  }

  var soft = 0;
  if (tail) {
    var f = last;
    while (f > first && around(f) < usual * 0.7) {
      f--;
    }
    soft = ((last - f) * frameMs).round();
  } else {
    var f = first;
    while (f < last && around(f) < usual * 0.5) {
      f++;
    }
    soft = ((f - first) * frameMs).round();
  }

  // Loudness of the eight seconds next to the edge.
  final from = tail ? max(first, last - 800) : first;
  final to = tail ? last : min(last, first + 800);
  var level = 0.0;
  for (var f = from; f <= to; f++) {
    level += loud[f];
  }
  level /= to - from + 1;

  // Tempo: the lag at which the rises of loudness best repeat.
  final rise = Float64List(frames);
  var mean = 0.0;
  for (var f = max(1, first); f <= last; f++) {
    rise[f] = max(0, loud[f] - loud[f - 1]);
    mean += rise[f];
  }
  mean /= last - first + 1;
  // Around their mean, or steady noise would look like a steady beat.
  var power = 0.0;
  for (var f = first; f <= last; f++) {
    power += (rise[f] - mean) * (rise[f] - mean);
  }
  double repeat(int lag) {
    var sum = 0.0;
    for (var f = first + lag; f <= last; f++) {
      sum += (rise[f] - mean) * (rise[f - lag] - mean);
    }
    return sum;
  }

  var best = 0.0;
  var bestLag = 0;
  // 180 beats a minute is a lag of 33 frames, 70 of 86.
  for (var lag = 33; lag <= 86; lag++) {
    final value = repeat(lag);
    if (value > best) {
      best = value;
      bestLag = lag;
    }
  }
  var bpm = 0.0;
  var beat = 0.0;
  var beatAt = offset;
  var bar = 0;
  if (bestLag > 0 && power > 0) {
    beat = (best / power).clamp(0.0, 1.0);
    // A held note ripples evenly too: hits must stand out of the loudness.
    final hits = sqrt(power / (last - first + 1)) / usual;
    beat *= (hits / 0.08).clamp(0.0, 1.0);
    // Many beats apart the same lag is that many times as precise.
    var period = bestLag.toDouble();
    for (final beats in [4, 16, 64]) {
      if (last - first < period * beats * 3) break;
      final centre = (period * beats).round();
      final reach = beats ~/ 2 + 2;
      var fine = 0.0;
      var fineLag = centre;
      for (var lag = centre - reach; lag <= centre + reach; lag++) {
        final value = repeat(lag);
        if (value > fine) {
          fine = value;
          fineLag = lag;
        }
      }
      final before = repeat(fineLag - 1);
      final after = repeat(fineLag + 1);
      final bend = before - 2 * fine + after;
      final shift = bend == 0 ? 0.0 : 0.5 * (before - after) / bend;
      period = (fineLag + shift.clamp(-0.5, 0.5)) / beats;
    }
    bpm = 60000 / (period * frameMs);

    // Where the beats fall: the shift of the grid that catches most rises.
    var bestScore = -1.0;
    var bestShift = 0;
    for (var shift = 0; shift < period; shift++) {
      var score = 0.0;
      for (var at = first + shift.toDouble(); at <= last; at += period) {
        score += rise[at.round().clamp(0, frames - 1)];
      }
      if (score > bestScore) {
        bestScore = score;
        bestShift = shift;
      }
    }
    beatAt = time(first + bestShift);
    var barScore = -1.0;
    for (var k = 0; k < 4; k++) {
      var score = 0.0;
      for (
        var at = first + bestShift + k * period;
        at <= last;
        at += 4 * period
      ) {
        score += rise[at.round().clamp(0, frames - 1)];
      }
      if (score > barScore) {
        barScore = score;
        bar = k;
      }
    }
  }

  final harmony = detectMixKey(samples, rate);
  return MixEdge(
    key: harmony.key,
    keyConfidence: harmony.confidence,
    sound: time(tail ? last + 1 : first),
    bpm: bpm,
    beat: beat,
    beatAt: beatAt,
    level: level,
    soft: soft,
    bar: bar,
  );
}

/// How far apart two tempos are, as a part of one (0.02 is 2%), a song at
/// half or double the other's tempo counting as the same.
double tempoGap(double a, double b) {
  if (a <= 0 || b <= 0) return 1;
  var ratio = a / b;
  while (ratio > 1.5) {
    ratio /= 2;
  }
  while (ratio < 0.75) {
    ratio *= 2;
  }
  return (ratio - 1).abs();
}

/// A stretch of a song that is skipped, in milliseconds.
typedef MixSkip = ({int start, int end});

/// What the skipped stretches leave of a song at its two ends: where it
/// really starts, and where it really ends (null: at its end).
({int start, int? end}) mixBounds(List<MixSkip> skips, Duration? duration) {
  final sorted = [...skips]..sort((a, b) => a.start.compareTo(b.start));
  var start = 0;
  for (final skip in sorted) {
    if (skip.start <= start + 2000 && skip.end > start) start = skip.end;
  }
  int? end;
  if (duration != null) {
    var last = duration.inMilliseconds;
    for (final skip in sorted.reversed) {
      if (skip.end >= last - 3000 && skip.start < last && skip.start > start) {
        end = last = skip.start;
      }
    }
  }
  return (start: start, end: end);
}

/// Keeps each deck in a continuous playable stretch during the overlap.
MixCue fitMixSkips(
  MixCue cue,
  List<MixSkip> outgoing,
  List<MixSkip> incoming,
  Duration duration,
  Duration? coming,
) {
  if (outgoing.isEmpty && incoming.isEmpty) return cue;
  final desired = cue.length.inMilliseconds;
  var exit = min(
    duration.inMilliseconds,
    (cue.outStart + cue.length).inMilliseconds,
  );
  var start = 0;
  for (final skip in outgoing.reversed) {
    if (skip.start >= exit) continue;
    if (skip.end < exit) {
      start = skip.end;
      break;
    }
    exit = skip.start;
  }
  var entry = cue.inStart.inMilliseconds;
  var end = coming?.inMilliseconds;
  for (final skip in incoming) {
    if (skip.end <= entry) continue;
    if (skip.start > entry) {
      end = end == null ? skip.start : min(end, skip.start);
      break;
    }
    entry = skip.end;
  }
  final length = max(
    0,
    min(
      desired,
      min(
        exit - start,
        end == null ? desired : ((end - entry) / cue.tempoRatio).floor(),
      ),
    ),
  );
  return MixCue(
    outStart: Duration(milliseconds: max(0, exit - length)),
    inStart: Duration(milliseconds: entry),
    length: Duration(milliseconds: length),
    style: cue.style,
    volume: cue.volume,
    eq: cue.eq,
    filter: cue.filter,
    tempoRatio: cue.tempoRatio,
  );
}

/// The Automatic transition: where and how a song of [duration] gives way
/// to the next, from the [tail] of the one and the [head] of the other.
/// The audio decides which styles fit; [pair] picks among them, so a
/// playlist gets variety and the same pair always the same transition.
/// [echo] says whether the outgoing player can echo on its beat. With an
/// end missing it is a plain crossfade until the analysis is done.
/// [endAt] and [startAt] keep it out of the skipped ends of the two songs.
MixCue chooseCue({
  required Duration duration,
  required Duration? coming,
  required MixEdge? tail,
  required MixEdge? head,
  required String pair,
  bool echo = false,
  int? endAt,
  int startAt = 0,
}) {
  final total = min(duration.inMilliseconds, endAt ?? duration.inMilliseconds);
  // Never more than a third of either song.
  var longest = total ~/ 3;
  if (coming != null && coming > Duration.zero) {
    longest = min(longest, coming.inMilliseconds ~/ 3);
  }
  MixCue cue(
    int out,
    int into,
    int length,
    MixStyle style, {
    double ratio = 1,
  }) => MixCue(
    outStart: Duration(milliseconds: out.clamp(0, total)),
    inStart: Duration(milliseconds: max(startAt, into)),
    length: Duration(milliseconds: max(500, length)),
    style: style,
    tempoRatio: ratio,
  );
  final seed = pair.codeUnits.fold(
    7,
    (hash, unit) => (hash * 31 + unit) & 0xffffff,
  );
  MixStyle pick(List<MixStyle> styles) => styles[seed % styles.length];

  if (tail == null || head == null) {
    final length = min(8000, longest);
    return cue(total - length, startAt, length, MixStyle.smooth);
  }

  final end = tail.sound.clamp(0, total);
  final start = max(head.sound, startAt);
  // A recorded fade out is mostly left out: the beat is weak in it, and a
  // DJ leaves where the energy goes, not where the sound ends.
  final last = end - tail.soft ~/ 2;

  if (tail.rhythmic && head.rhythmic) {
    final beatMs = 60000 / tail.bpm;
    final inBeat = 60000 / head.bpm;
    // The new song's first beat after its silence.
    final firstBeat =
        (head.beatAt + ((start - head.beatAt) / inBeat).ceil() * inBeat)
            .round();
    int onBeat(int before) =>
        (tail.beatAt + ((before - tail.beatAt) / beatMs).floor() * beatMs)
            .round();
    final clash = harmonicDistance(tail.key, head.key) > 1;
    final gap = tempoGap(tail.bpm, head.bpm);
    if (gap <= 0.06 && tail.beat >= 0.25 && head.beat >= 0.25) {
      // Tempos that meet: the beats are laid on each other and the new song
      // is brought to the old one's tempo.
      final quieter = head.level < tail.level * 0.7;
      final louder = head.level > tail.level * 1.4;
      final steady = tail.beat > 0.5 && head.beat > 0.5;
      final style = clash
          ? pick([MixStyle.melt, if (echo) MixStyle.echo, MixStyle.slam])
          : quieter
          ? pick([MixStyle.rise, MixStyle.sweep])
          : louder
          ? pick([MixStyle.wave, MixStyle.slam, MixStyle.sweep])
          : steady
          ? pick([MixStyle.blend, MixStyle.fade, MixStyle.sweep, MixStyle.wave])
          : pick([MixStyle.fade, MixStyle.sweep, MixStyle.rise]);
      var beats = switch (style) {
        MixStyle.blend => 32,
        MixStyle.melt || MixStyle.echo || MixStyle.slam => 8,
        _ => 16,
      };
      while (beats > 4 && beatMs * beats > min(32000, longest)) {
        beats ~/= 2;
      }
      final length = (beatMs * beats).round();
      // A cut lands on a beat of both songs.
      final lead = switch (style.volume) {
        MixVolume.cutIn => length ~/ 4,
        MixVolume.centerCut => length ~/ 2,
        _ => 0,
      };
      return cue(
        onBeat(last - length),
        lead == 0
            ? firstBeat
            : firstBeat - (lead * head.bpm / tail.bpm).round(),
        length,
        style,
        ratio: tempoRatio(tail.bpm, head.bpm),
      );
    }
    // Beats that do not meet: the old song gets out of the way on its own
    // beat, by an echo, a cut after a sweep, or by thinning out.
    final style = pick([
      if (echo) ...[MixStyle.echo, MixStyle.echo],
      MixStyle.slam,
      MixStyle.melt,
    ]);
    final length = min((beatMs * 8).round().clamp(3000, 8000), longest);
    final lead = switch (style.volume) {
      MixVolume.cutIn => length ~/ 4,
      MixVolume.centerCut => length ~/ 2,
      _ => 0,
    };
    return cue(
      onBeat(last - length),
      lead == 0 ? start : firstBeat - lead,
      length,
      style,
    );
  }

  if (tail.soft >= 4000) {
    // The old song fades out on the record: the new one rises under it, or
    // a filter takes the old one away as its fade starts.
    final style = pick([MixStyle.under, MixStyle.sweep]);
    final length = min(tail.soft.clamp(4000, 10000), longest);
    return cue(
      style == MixStyle.under ? end - length : end - tail.soft,
      start,
      length,
      style,
    );
  }

  if (tail.soft < 700 && tail.level > 0.02) {
    // A sudden ending is kept whole: the new song comes in right on it.
    final length = min(2000, longest);
    return cue(end - length ~/ 2, start, length, MixStyle.under);
  }

  // Quiet or free songs: calm, or a filter.
  final style = pick([MixStyle.smooth, MixStyle.sweep, MixStyle.smooth]);
  final length = min(style == MixStyle.sweep ? 8000 : 6000, longest);
  return cue(end - length, start, length, style);
}

/// Where a song can be read from: a file path or an address, with the
/// headers the address needs.
typedef MixLocation = ({String source, Map<String, String>? headers});

/// A bounded envelope for the editor, in source-song time. PCM is discarded.
typedef MixInspection = ({
  MixEdge edge,
  List<double> wave,
  int offset,
  int length,
});

List<double> mixEnvelope(Int16List samples, {int bins = 400}) {
  if (samples.isEmpty || bins <= 0) return const [];
  final count = min(bins, samples.length);
  return List.generate(count, (i) {
    final from = i * samples.length ~/ count;
    final to = (i + 1) * samples.length ~/ count;
    var sum = 0.0;
    for (var at = from; at < to; at++) {
      sum += samples[at] * samples[at];
    }
    return sqrt(sum / (to - from)) / 32768;
  });
}

typedef _WholeSong = ({
  MixEdge head,
  MixEdge tail,
  List<double> wave,
  int length,
});

/// Reads a whole decoded song from the file at [path]: both its ends and its
/// waveform, a tenth of a second each bar, scaled to its loudest.
({MixEdge head, MixEdge tail, List<double> wave, int length})? inspectPcm(
  String path,
  int rate,
) {
  final bytes = File(path).readAsBytesSync();
  final samples = bytes.buffer.asInt16List(0, bytes.length ~/ 2);
  if (samples.isEmpty || rate <= 0) return null;
  final ms = (samples.length * 1000 / rate).round();
  final edge = min(samples.length, MixAnalyzer.stretch.inSeconds * rate);
  final from = samples.length - edge;
  final wave = mixEnvelope(samples, bins: (ms ~/ 100).clamp(400, 3000));
  final peak = max(0.0001, wave.reduce(max));
  // Tempo and key read over the whole song: an end with no beat, or that is
  // short on notes, takes them from the song as a whole.
  final song = analyzeEdge(samples, rate, offset: 0, tail: false);
  MixEdge ofSong(MixEdge edge) {
    final key = song.key ?? edge.key;
    final keyConfidence = song.key == null
        ? edge.keyConfidence
        : song.keyConfidence;
    if (!song.rhythmic ||
        (edge.rhythmic && tempoGap(edge.bpm, song.bpm) > 0.03)) {
      return MixEdge(
        sound: edge.sound,
        bpm: edge.bpm,
        beat: edge.beat,
        beatAt: edge.beatAt,
        level: edge.level,
        soft: edge.soft,
        key: key,
        keyConfidence: keyConfidence,
        bar: edge.bar,
      );
    }
    return MixEdge(
      sound: edge.sound,
      bpm: song.bpm,
      beat: max(edge.beat, song.beat),
      beatAt: song.beatAt,
      level: edge.level,
      soft: edge.soft,
      key: key,
      keyConfidence: keyConfidence,
      bar: song.bar,
    );
  }

  return (
    head: ofSong(
      analyzeEdge(
        Int16List.sublistView(samples, 0, edge),
        rate,
        offset: 0,
        tail: false,
      ),
    ),
    tail: ofSong(
      analyzeEdge(
        Int16List.sublistView(samples, from),
        rate,
        offset: (from * 1000 / rate).round(),
        tail: true,
      ),
    ),
    wave: [for (final value in wave) value / peak],
    length: ms,
  );
}

/// Analyses the ends of songs in the background, one at a time, and keeps
/// what it found: in memory, and for a month in the cache.
class MixAnalyzer {
  MixAnalyzer({required this.locate});

  /// A beat at least this steady can be mixed on.
  static const steadyBeat = 0.18;

  /// How much of each end is read.
  static const stretch = Duration(seconds: 40);

  static const _channel = MethodChannel('zenify/audio_decode');

  /// Finds where a song can be read from; null when it cannot be now.
  final Future<MixLocation?> Function(Map song) locate;

  final _edges = <String, MixEdge?>{};
  final _asked = <String>{};
  final _retryAfter = <String, DateTime>{};

  /// Moves each time an end of a song was analysed.
  final changes = ValueNotifier<int>(0);
  Future<void> _queue = Future.value();

  /// The longest song the editor reads whole.
  static const longest = Duration(minutes: 20);

  final _songs = <String, _WholeSong>{};
  final _reading = <String, Future<_WholeSong?>>{};
  Future<void> _editorQueue = Future.value();

  /// The whole waveform of [song] and one of its ends, for the editor. One
  /// decoding serves both ends, on a queue of its own: playback's analyses
  /// do not hold the editor.
  Future<MixInspection?> inspect(
    Map song, {
    required bool tail,
    required Duration? duration,
  }) async {
    final id = song['ytid']?.toString();
    if (id == null || id.isEmpty) return null;
    final whole =
        _songs[id] ??
        _stored(song, id) ??
        await (_reading[id] ??=
            _read(Map<dynamic, dynamic>.of(song), id, duration).whenComplete(
              () {
                _reading.remove(id);
              },
            ));
    if (whole == null) return null;
    return (
      edge: tail ? whole.tail : whole.head,
      wave: whole.wave,
      offset: 0,
      length: whole.length,
    );
  }

  static String _waveKey(String id) => 'mix_v3_wave_$id';

  void _remember(String id, _WholeSong whole) {
    _songs.remove(id);
    _songs[id] = whole;
    if (_songs.length > 8) _songs.remove(_songs.keys.first);
  }

  /// A song read before: its waveform is kept with its ends.
  _WholeSong? _stored(Map song, String id) {
    final head = edge(song, tail: false);
    final tail = edge(song, tail: true);
    final stored = Hive.box('cache').get(_waveKey(id));
    if (head == null || tail == null || stored is! Uint8List) return null;
    if (stored.length < 5) return null;
    final whole = (
      head: head,
      tail: tail,
      wave: [for (final value in stored.skip(4)) value / 255],
      length: ByteData.sublistView(stored).getUint32(0),
    );
    _remember(id, whole);
    return whole;
  }

  Future<_WholeSong?> _read(Map song, String id, Duration? duration) {
    final result = Completer<_WholeSong?>();
    _editorQueue = _editorQueue.then((_) async {
      File? scratch;
      try {
        final where = await locate(song);
        if (where == null || (duration != null && duration > longest)) {
          result.complete(null);
          return;
        }
        final dir = await getTemporaryDirectory();
        scratch = File(
          '${dir.path}/mix_whole_${DateTime.now().microsecondsSinceEpoch}.pcm',
        );
        final rate = await _decodeTo(
          where,
          Duration.zero,
          // A song of unknown length is read to its end.
          duration == null ? longest : duration + const Duration(seconds: 1),
          scratch.path,
        );
        if (rate <= 0 || !scratch.existsSync()) {
          result.complete(null);
          return;
        }
        final whole = await _wholeInIsolate(scratch.path, rate);
        // Cut short at the limit: its end would not be the song's.
        if (whole == null ||
            (duration == null &&
                whole.length > longest.inMilliseconds - 2000)) {
          result.complete(null);
          return;
        }
        _remember(id, whole);
        _edges[_key(id, false)] = whole.head;
        _edges[_key(id, true)] = whole.tail;
        final packed = Uint8List(4 + whole.wave.length);
        ByteData.sublistView(packed).setUint32(0, whole.length);
        for (var i = 0; i < whole.wave.length; i++) {
          packed[4 + i] = (whole.wave[i] * 255).round().clamp(0, 255);
        }
        await addOrUpdateData<List<num>>(
          'cache',
          _key(id, false),
          whole.head.toList(),
        );
        await addOrUpdateData<List<num>>(
          'cache',
          _key(id, true),
          whole.tail.toList(),
        );
        await addOrUpdateData<Uint8List>('cache', _waveKey(id), packed);
        changes.value++;
        result.complete(whole);
      } catch (e, stackTrace) {
        logger.log(
          'Mix: editor analysis failed',
          error: e,
          stackTrace: stackTrace,
        );
        if (!result.isCompleted) result.complete(null);
      } finally {
        if (scratch != null && scratch.existsSync())
          unawaited(scratch.delete());
      }
    });
    return result.future;
  }

  // Static: the isolate reads the file itself, so no samples are copied.
  static Future<_WholeSong?> _wholeInIsolate(String path, int rate) =>
      Isolate.run(() => inspectPcm(path, rate));

  static String _key(String id, bool tail) =>
      'mix_v2_edge_${id}_${tail ? 'tail' : 'head'}';

  /// What is known of an end of [song]; null until it was analysed.
  MixEdge? edge(Map song, {required bool tail}) {
    final id = song['ytid']?.toString();
    if (id == null || id.isEmpty) return null;
    final key = _key(id, tail);
    if (_edges.containsKey(key)) return _edges[key];
    final stored = Hive.box('cache').get(key);
    if (stored is List &&
        (stored.length == 6 || stored.length == 8 || stored.length == 9)) {
      try {
        return _edges[key] = MixEdge.fromList(stored);
      } catch (_) {}
    }
    return null;
  }

  /// Asks for an end of [song] to be analysed, once. The tail needs the
  /// song's [duration].
  void want(Map song, {required bool tail, Duration? duration}) {
    final id = song['ytid']?.toString();
    if (id == null || id.isEmpty) return;
    final key = _key(id, tail);
    if (_asked.contains(key) || edge(song, tail: tail) != null) return;
    if (_retryAfter[key]?.isAfter(DateTime.now()) == true) return;
    if (tail && (duration == null || duration <= Duration.zero)) return;
    _asked.add(key);
    final data = Map<dynamic, dynamic>.of(song);
    _queue = _queue.then((_) async {
      try {
        final found = await _analyse(data, tail: tail, duration: duration);
        _edges[key] = found;
        changes.value++;
        if (found != null) {
          await addOrUpdateData<List<num>>('cache', key, found.toList());
        } else {
          _asked.remove(key);
          _retryAfter[key] = DateTime.now().add(const Duration(seconds: 30));
        }
      } catch (e, stackTrace) {
        _edges[key] = null;
        _asked.remove(key);
        _retryAfter[key] = DateTime.now().add(const Duration(seconds: 30));
        logger.log('Mix: analysis failed', error: e, stackTrace: stackTrace);
      }
    });
  }

  Future<MixEdge?> _analyse(
    Map song, {
    required bool tail,
    Duration? duration,
  }) async {
    final where = await locate(song);
    if (where == null) return null;
    final length = tail && duration! < stretch ? duration : stretch;
    final decoded = await decode(
      where,
      start: tail ? -length : Duration.zero,
      length: length,
    );
    if (decoded == null || decoded.samples.isEmpty) return null;
    final read = (decoded.samples.length * 1000 / decoded.rate).round();
    final offset = tail ? max(0, duration!.inMilliseconds - read) : 0;
    return _inIsolate(decoded.samples, decoded.rate, offset, tail);
  }

  // Static, so the isolate is sent these values and nothing else.
  static Future<MixEdge> _inIsolate(
    Int16List samples,
    int rate,
    int offset,
    bool tail,
  ) {
    final data = TransferableTypedData.fromList([samples]);
    return Isolate.run(
      () => analyzeEdge(
        data.materialize().asInt16List(),
        rate,
        offset: offset,
        tail: tail,
      ),
    );
  }

  /// Decodes [length] of a song from [start] to mono samples, without
  /// playing it; a negative start counts from the end.
  static Future<({Int16List samples, int rate})?> decode(
    MixLocation where, {
    required Duration start,
    required Duration length,
  }) async {
    final dir = await getTemporaryDirectory();
    final scratch = File(
      '${dir.path}/mix_decode_${DateTime.now().microsecondsSinceEpoch}.pcm',
    );
    try {
      final rate = await _decodeTo(where, start, length, scratch.path);
      if (rate <= 0 || !scratch.existsSync()) return null;
      final bytes = await scratch.readAsBytes();
      return (
        samples: bytes.buffer.asInt16List(0, bytes.length ~/ 2),
        rate: rate,
      );
    } finally {
      if (scratch.existsSync()) unawaited(scratch.delete());
    }
  }

  /// Writes the samples to the file [out]; returns their rate, 0 on failure.
  static Future<int> _decodeTo(
    MixLocation where,
    Duration start,
    Duration length,
    String out,
  ) async {
    if (isAndroidPlatform) {
      return await _channel.invokeMethod<int>('decode', {
            'source': where.source,
            'headers': where.headers,
            'startMs': start.inMilliseconds,
            'lengthMs': length.inMilliseconds,
            'out': out,
          }) ??
          0;
    }
    if (isDesktopPlatform) return _decodeWithMpv(where, start, length, out);
    return 0;
  }

  /// An mpv of its own writes the stretch to a file as fast as it decodes.
  static Future<int> _decodeWithMpv(
    MixLocation where,
    Duration start,
    Duration length,
    String out,
  ) async {
    const rate = 11025;
    final player = Player(
      configuration: const PlayerConfiguration(title: 'zenify-analysis'),
    );
    try {
      final native = player.platform! as NativePlayer;
      final headers = Map<String, String>.of(where.headers ?? const {});
      final agent = headers.remove('user-agent');
      final properties = {
        'ao': 'pcm',
        'ao-pcm-file': out,
        'ao-pcm-waveheader': 'no',
        'audio-samplerate': '$rate',
        'audio-channels': 'mono',
        'audio-format': 's16',
        'vid': 'no',
        'start': (start.inMilliseconds / 1000).toStringAsFixed(3),
        'length': (length.inMilliseconds / 1000).toStringAsFixed(3),
        if (agent != null) 'user-agent': agent,
        if (headers.isNotEmpty)
          'http-header-fields': [
            for (final MapEntry(:key, :value) in headers.entries)
              '$key: ${value.replaceAll(',', r'\,')}',
          ].join(','),
      };
      for (final MapEntry(:key, :value) in properties.entries) {
        await native.setProperty(key, value);
      }
      // Either stream closes with the player: that is not an error here.
      final done = player.stream.completed
          .firstWhere((completed) => completed)
          .then<Object>((value) => value, onError: (_) => false);
      final failed = player.stream.error.first.then<Object>(
        (error) => error,
        onError: (_) => false,
      );
      await player.open(Media(where.source));
      final result = await Future.any<Object>([done, failed])
          .timeout(const Duration(seconds: 90));
      return result == true ? rate : 0;
    } on TimeoutException {
      return 0;
    } finally {
      await player.dispose();
    }
  }
}
