import 'package:musify/services/mix_analysis.dart';
import 'package:musify/services/mix_harmony.dart';

/// Greedy harmonic path anchored at the first song. Unknown songs keep their
/// relative order at the end. Does not mutate the playlist or its saved pairs.
List<Map> orderMixSongs(List<Map> songs, MixAnalyzer analyzer) {
  if (songs.length < 2) return List.of(songs);
  MixEdge? head(Map s) => analyzer.edge(s, tail: false);
  final remaining = songs
      .skip(1)
      .where((s) => head(s)?.rhythmic == true)
      .toList();
  final unknown = songs
      .skip(1)
      .where((s) => head(s)?.rhythmic != true)
      .toList();
  final result = <Map>[songs.first];
  while (remaining.isNotEmpty) {
    final previous =
        analyzer.edge(result.last, tail: true) ?? head(result.last);
    double cost(Map s) {
      final edge = head(s)!;
      if (previous == null || !previous.rhythmic) return 0;
      return tempoGap(previous.bpm, edge.bpm) * 40 +
          harmonicDistance(previous.key, edge.key) * 0.8 +
          (previous.level - edge.level).abs();
    }

    var best = 0;
    for (var i = 1; i < remaining.length; i++) {
      if (cost(remaining[i]) < cost(remaining[best])) best = i;
    }
    result.add(remaining.removeAt(best));
  }
  return [...result, ...unknown];
}
