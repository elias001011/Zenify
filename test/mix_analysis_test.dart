import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/mix_analysis.dart';
import 'package:musify/services/mix_transition.dart';
import 'package:musify/widgets/mix_chip.dart';

const _rate = 11025;

/// Forty seconds of a made-up song: a bass note, some noise, and a drum hit
/// on every beat when [bpm] is given. [shape] is its loudness (0 to 1) at
/// each second.
Int16List _song({double? bpm, double Function(double seconds)? shape}) {
  final random = Random(7);
  final samples = Int16List(_rate * 40);
  for (var i = 0; i < samples.length; i++) {
    final t = i / _rate;
    var value =
        0.15 * sin(2 * pi * 110 * t) + 0.03 * (random.nextDouble() - .5);
    if (bpm != null) {
      final sinceBeat = t % (60 / bpm);
      if (sinceBeat < 0.06) {
        value += 0.6 * sin(2 * pi * 60 * sinceBeat) * (1 - sinceBeat / 0.06);
      }
    }
    samples[i] = (value * (shape?.call(t) ?? 1) * 32767).round().clamp(
      -32768,
      32767,
    );
  }
  return samples;
}

MixEdge _edge(String name, MixEdge edge) {
  // ignore: avoid_print
  print(
    '$name: sound=${edge.sound} bpm=${edge.bpm.toStringAsFixed(2)} '
    'beat=${edge.beat.toStringAsFixed(2)} beatAt=${edge.beatAt} '
    'level=${edge.level.toStringAsFixed(3)} soft=${edge.soft}',
  );
  return edge;
}

void main() {
  group('analyzeEdge', () {
    for (final bpm in [92.0, 120.0, 128.0, 174.0]) {
      test('finds a tempo of $bpm', () {
        final edge = _edge(
          'bpm $bpm',
          analyzeEdge(_song(bpm: bpm), _rate, offset: 0, tail: false),
        );
        expect(tempoGap(edge.bpm, bpm), lessThan(0.01));
        expect(edge.rhythmic, isTrue);
        // A beat falls on the grid of the drum hits, which starts at zero.
        final beatMs = 60000 / bpm;
        final off = edge.beatAt % beatMs;
        expect(min(off, beatMs - off), lessThan(40));
      });
    }

    test('a song with no drums has no steady beat', () {
      final edge = _edge(
        'no drums',
        analyzeEdge(_song(), _rate, offset: 0, tail: false),
      );
      expect(edge.rhythmic, isFalse);
    });

    test('the head starts where the sound does', () {
      final edge = _edge(
        'silent start',
        analyzeEdge(
          _song(bpm: 120, shape: (t) => t < 2.5 ? 0 : 1),
          _rate,
          offset: 0,
          tail: false,
        ),
      );
      expect(edge.sound, closeTo(2500, 60));
      expect(edge.soft, lessThan(700));
    });

    test('a soft intro is measured', () {
      final edge = _edge(
        'soft intro',
        analyzeEdge(
          _song(shape: (t) => (t / 8).clamp(0.02, 1)),
          _rate,
          offset: 0,
          tail: false,
        ),
      );
      expect(edge.soft, inInclusiveRange(2500, 5500));
    });

    test('the tail ends where the sound does, in the time of the song', () {
      final edge = _edge(
        'silent end',
        analyzeEdge(
          _song(bpm: 120, shape: (t) => t > 36 ? 0 : 1),
          _rate,
          // The forty seconds are the end of a song of 200.
          offset: 160000,
          tail: true,
        ),
      );
      expect(edge.sound, closeTo(196000, 120));
      expect(edge.soft, lessThan(700), reason: 'a sudden ending');
    });

    test('a recorded fade out is measured', () {
      final edge = _edge(
        'fade out',
        analyzeEdge(
          _song(bpm: 120, shape: (t) => t < 28 ? 1 : max(0, 1 - (t - 28) / 10)),
          _rate,
          offset: 0,
          tail: true,
        ),
      );
      expect(edge.soft, inInclusiveRange(4500, 9500));
    });

    test('silence gives an empty edge instead of failing', () {
      final edge = analyzeEdge(
        Int16List(_rate * 10),
        _rate,
        offset: 0,
        tail: true,
      );
      expect(edge.rhythmic, isFalse);
      expect(edge.level, 0);
    });
  });

  group('chooseCue', () {
    const duration = Duration(seconds: 200);
    MixEdge tail({double bpm = 120, double beat = 0.8, int soft = 1500}) =>
        MixEdge(
          sound: 198000,
          bpm: bpm,
          beat: beat,
          beatAt: 160000,
          level: 0.2,
          soft: soft,
        );
    MixEdge head({double bpm = 120, double beat = 0.8}) => MixEdge(
      sound: 300,
      bpm: bpm,
      beat: beat,
      beatAt: 420,
      level: 0.2,
      soft: 200,
    );
    MixCue choose(MixEdge? tail, MixEdge? head, {String pair = 'a>b'}) =>
        chooseCue(
          duration: duration,
          coming: const Duration(seconds: 180),
          tail: tail,
          head: head,
          pair: pair,
        );

    test('without analysis it is a plain crossfade at the end', () {
      final cue = choose(null, null);
      expect(cue.style, MixStyle.smooth);
      expect(cue.length, const Duration(seconds: 8));
      expect(cue.outStart, const Duration(seconds: 192));
      expect(cue.inStart, Duration.zero);
    });

    test('the same tempo mixes sixteen beats, on the beat of both', () {
      final cue = choose(tail(), head());
      expect(cue.length, const Duration(seconds: 8));
      // The old song leaves on its grid (beats every 500 ms from 160 s) and
      // is done before its sound ends.
      expect((cue.outStart.inMilliseconds - 160000) % 500, 0);
      expect(cue.outStart + cue.length, lessThanOrEqualTo(_ms(198000)));
      // The new one comes in on its first beat after the silence.
      expect(cue.inStart, _ms(420));
      expect(cue.style.eq, isNot(MixEq.none), reason: 'the basses swap');
    });

    test('half and double tempo count as the same', () {
      expect(choose(tail(bpm: 70), head(bpm: 140)).style.eq, isNot(MixEq.none));
      expect(tempoGap(70, 140), 0);
    });

    test('identical audio chooses the same style regardless of pair id', () {
      final styles = {
        for (var i = 0; i < 40; i++)
          choose(tail(), head(), pair: 'x$i>y').style,
      };
      expect(styles.length, 1);
      expect(
        choose(tail(), head(), pair: 'x1>y').style,
        choose(tail(), head(), pair: 'x1>y').style,
      );
    });

    test(
      'tempos that do not match get a short mix that thins the old song',
      () {
        final cue = choose(tail(), head(bpm: 97));
        expect(cue.style, MixStyle.melt);
        expect(cue.length.inMilliseconds, inInclusiveRange(3000, 6000));
        expect(cue.outStart + cue.length, _ms(198000));
        expect(cue.inStart, _ms(300));
      },
    );

    test('a recorded fade out lets the new song rise under it', () {
      final cue = choose(tail(beat: 0.1, soft: 7000), head(beat: 0.1));
      expect(cue.style, MixStyle.under);
      expect(cue.length, const Duration(seconds: 7));
      expect(cue.outStart, _ms(191000));
    });

    test('a sudden ending is kept: the new song comes in right on it', () {
      final cue = choose(tail(beat: 0.1, soft: 200), head(beat: 0.1));
      expect(cue.style, MixStyle.under);
      expect(cue.outStart, _ms(197000));
      expect(cue.length, const Duration(seconds: 2));
    });

    test('never longer than a third of a short song', () {
      final cue = chooseCue(
        duration: const Duration(seconds: 15),
        coming: const Duration(seconds: 12),
        tail: null,
        head: null,
        pair: 'a>b',
      );
      expect(cue.length, const Duration(seconds: 4));
    });
  });

  group('mixChipLabel', () {
    MixEdge edge(double bpm, {bool tail = false, double beat = 0.8}) => MixEdge(
      sound: tail ? 198000 : 300,
      bpm: bpm,
      beat: beat,
      beatAt: tail ? 160000 : 400,
      level: 0.2,
      soft: 500,
    );
    const a = {'ytid': 'a', 'duration': 200};
    const b = {'ytid': 'b', 'duration': 200};

    test('is Auto until both songs were analysed', () {
      expect(mixChipLabel(a, b), 'Auto');
      expect(mixChipLabel(a, b, tail: edge(120, tail: true)), 'Auto');
    });

    test('names the style and the tempos', () {
      expect(
        mixChipLabel(a, b, tail: edge(120, tail: true), head: edge(97)),
        'Melt · 120 → 97 BPM',
      );
      expect(
        mixChipLabel(a, b, tail: edge(120, tail: true), head: edge(120)),
        matches(r'^(Fade|Wave|Blend|Rise) · 120 BPM$'),
      );
      expect(
        mixChipLabel(
          a,
          b,
          tail: edge(120, tail: true, beat: 0),
          head: edge(97, beat: 0),
        ),
        isNot(contains('BPM')),
      );
    });
  });

  group('mixFrame', () {
    test(
      'every style starts with only the old song and ends with only the new',
      () {
        for (final style in MixStyle.values) {
          final start = mixFrame(style, 0);
          final end = mixFrame(style, 1);
          expect(start.outGain, closeTo(1, 1e-9), reason: '$style');
          expect(start.inGain, closeTo(0, 1e-9), reason: '$style');
          expect(start.outBands, mixFlat, reason: '$style');
          expect(end.inGain, closeTo(1, 1e-9), reason: '$style');
          expect(end.outGain, closeTo(0, 1e-9), reason: '$style');
          expect(end.inBands, mixFlat, reason: '$style');
        }
      },
    );

    test('no style jumps: gains and bands move in small steps', () {
      for (final style in MixStyle.values) {
        if (style == MixStyle.slam) continue;
        var before = mixFrame(style, 0);
        for (var i = 1; i <= 160; i++) {
          final now = mixFrame(style, i / 160);
          expect((now.outGain - before.outGain).abs(), lessThan(0.1));
          expect((now.inGain - before.inGain).abs(), lessThan(0.1));
          expect((now.outBands.low - before.outBands.low).abs(), lessThan(7));
          expect((now.inBands.high - before.inBands.high).abs(), lessThan(7));
          before = now;
        }
      }
    });

    test('with a bass swap the two basses together are as loud as one', () {
      for (final style in [MixStyle.fade, MixStyle.wave, MixStyle.rise]) {
        for (var i = 0; i <= 100; i++) {
          final frame = mixFrame(style, i / 100);
          final power =
              pow(10, frame.outBands.low / 10) +
              pow(10, frame.inBands.low / 10);
          expect(power, inInclusiveRange(0.95, 1.01), reason: '$style $i');
        }
      }
    });
  });
}

Duration _ms(int value) => Duration(milliseconds: value);
