import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/mix_analysis.dart';
import 'package:musify/services/mix_edits.dart';
import 'package:musify/services/mix_harmony.dart';
import 'package:musify/services/mix_playlist_analysis.dart';
import 'package:musify/services/mix_transition.dart';

class _Analyzed extends MixAnalyzer {
  _Analyzed(this.edges) : super(locate: (_) async => null);
  final Map<String, MixEdge> edges;
  @override
  MixEdge? edge(Map song, {required bool tail}) => edges[song['ytid']];
}

MixEdge edge({
  double bpm = 120,
  double level = 0.2,
  int? key,
  double beat = 0.8,
  bool tail = false,
}) => MixEdge(
  sound: tail ? 198000 : 500,
  bpm: bpm,
  beat: beat,
  beatAt: tail ? 160000 : 500,
  level: level,
  soft: 1000,
  key: key,
);
void main() {
  test(
    'nearby tempos synchronize and distant tempos isolate the outgoing beat',
    () {
      MixCue choose(double bpm) => chooseCue(
        duration: const Duration(seconds: 200),
        coming: const Duration(seconds: 200),
        tail: edge(tail: true),
        head: edge(bpm: bpm),
        pair: 'a>b',
      );
      expect(choose(125).tempoRatio, closeTo(0.96, 1e-9));
      // On the beat: a whole number of the old song's beats.
      expect(choose(125).length.inMilliseconds % 500, 0);
      expect(choose(150).tempoRatio, 1);
      expect(choose(150).style, isIn([MixStyle.slam, MixStyle.melt]));
    },
  );
  test('energy and incompatible keys change the automatic recipe', () {
    MixStyle choose(MixEdge head) => chooseCue(
      duration: const Duration(seconds: 200),
      coming: const Duration(seconds: 200),
      tail: edge(tail: true, key: 0),
      head: head,
      pair: 'same',
    ).style;
    expect(
      choose(edge(level: 0.08, key: 0)),
      isIn([MixStyle.rise, MixStyle.sweep]),
    );
    expect(
      choose(edge(level: 0.4, key: 0)),
      isIn([MixStyle.wave, MixStyle.slam, MixStyle.sweep]),
    );
    expect(choose(edge(key: 6)), isIn([MixStyle.melt, MixStyle.slam]));
  });
  test('sync duration respects actual incoming audio and independent controls survive storage', () {
    const edit = MixEdit(
      outStart: Duration(seconds: 160),
      inStart: Duration(seconds: 160),
      length: Duration(seconds: 40),
      style: MixStyle.wave,
      tempoRatio: 1.06,
      volume: MixVolume.fadeOutIn,
      eq: MixEq.threeBand,
      filter: MixFilter.both,
    );
    final restored = MixEdit.parse(edit.toList())!;
    final cue = restored.cue(
      const Duration(seconds: 200),
      const Duration(seconds: 200),
    );
    expect(cue.length.inMilliseconds, 37735);
    expect(
      restored
          .cue(const Duration(milliseconds: 1), const Duration(milliseconds: 1))
          .length,
      const Duration(milliseconds: 1),
    );
    expect(cue.volume, MixVolume.fadeOutIn);
    expect(cue.eq, MixEq.threeBand);
    expect(cue.filter, MixFilter.both);
    expect(cue.frame(0.5).inGain, lessThan(0.2));
    expect(MixEdit.parse([1000, 0, 8000, 'wave'])!.tempoRatio, 1);
  });
  test('harmonic ordering keeps first song and unknown tracks stable', () {
    final analyzer = _Analyzed({
      'a': edge(bpm: 120, key: 0),
      'b': edge(bpm: 160, key: 6),
      'c': edge(bpm: 122, key: 0),
    });
    final songs = [
      for (final id in ['a', 'unknown1', 'b', 'unknown2', 'c']) {'ytid': id},
    ];
    expect(orderMixSongs(songs, analyzer).map((s) => s['ytid']), [
      'a',
      'c',
      'b',
      'unknown1',
      'unknown2',
    ]);
    expect(songs[1]['ytid'], 'unknown1');
  });
  test(
    'silence has no fabricated key and tonal chord yields compatible estimate',
    () {
      expect(detectMixKey(Int16List(11025 * 3), 11025).key, isNull);
      final notes = [261.6256, 329.6276, 391.9954];
      final samples = Int16List.fromList(
        List.generate(
          11025 * 3,
          (i) =>
              (notes.fold<double>(
                        0,
                        (v, f) => v + sin(2 * pi * f * i / 11025),
                      ) *
                      5000)
                  .round(),
        ),
      );
      final found = detectMixKey(samples, 11025);
      expect(found.key, isNotNull);
      expect(harmonicDistance(found.key, 0), lessThanOrEqualTo(1));
    },
  );
}
