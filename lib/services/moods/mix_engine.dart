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

import 'dart:math';

import 'package:musify/services/moods/taste.dart';

/// How much of a queue is new to the user.
enum Discovery {
  familiar(0.4),
  balanced(0.65),
  adventurous(0.85),

  /// Only songs the user has never heard, liked or kept.
  onlyNew(1);

  const Discovery(this.newShare);
  final double newShare;
}

/// Scores the songs of seed radios: a song YouTube Music puts near the top of
/// the radios of strong seeds, or of several seeds, scores higher, and so
/// does an artist the user listens to. [radios] maps a seed's id to its radio,
/// in order; [accept] can turn a song away (a mood keeps to its pool).
Map<String, ({Map song, double score})> scoreRadios({
  required Taste taste,
  required Map<String, List<Map>> radios,
  required Map<String, double> seedWeights,
  bool Function(Map song)? accept,
}) {
  final scores = <String, ({Map song, double score})>{};
  for (final radio in radios.entries) {
    final weight = seedWeights[radio.key] ?? 0;
    final songs = radio.value;
    for (var i = 0; i < songs.length; i++) {
      final song = songs[i];
      final id = song['ytid']?.toString() ?? '';
      if (id.isEmpty || !looksLikeSong(song)) continue;
      if (accept != null && !accept(song)) continue;
      final gain = weight * (1 - i / songs.length);
      final previous = scores[id];
      scores[id] = (
        song: previous?.song ?? song,
        score: (previous?.score ?? taste.affinity(song) * 0.3) + gain,
      );
    }
  }
  return scores;
}

/// Picks [length] songs from [scored]: the share of new songs [discovery]
/// asks for, the best of each first with a little shuffle from [random], at
/// most [perArtist] per artist and never the same artist twice in a row.
/// Songs by [excludedArtists] (keys) are left out.
List<Map> assembleQueue({
  required Taste taste,
  required Map<String, ({Map song, double score})> scored,
  Discovery discovery = Discovery.balanced,
  int length = 40,
  int perArtist = 3,
  Set<String> excludedArtists = const {},
  Random? random,
}) {
  final shuffle = random ?? Random();
  // A little noise keeps two queues of the same mood from being twins.
  double jitter(double score) => score * (0.85 + shuffle.nextDouble() * 0.3);
  final ranked =
      scored.values
          .where((e) => !excludedArtists.contains(artistKey(e.song['artist'])))
          .map((e) => (song: e.song, score: jitter(e.score)))
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));

  final fresh = <Map>[];
  final familiar = <Map>[];
  for (final e in ranked) {
    final known = taste.known.contains(e.song['ytid']?.toString());
    if (!known) {
      fresh.add(e.song);
    } else if (discovery != Discovery.onlyNew) {
      familiar.add(e.song);
    }
  }

  final perArtistCount = <String, int>{};
  bool fits(Map song) {
    final key = artistKey(song['artist']);
    return (perArtistCount[key] ?? 0) < perArtist;
  }

  // Alternate between the two lists so the new share holds along the queue.
  final picked = <Map>[];
  var freshIndex = 0;
  var familiarIndex = 0;
  var newCount = 0;
  while (picked.length < length) {
    final wantNew =
        familiarIndex >= familiar.length ||
        (freshIndex < fresh.length &&
            newCount < discovery.newShare * (picked.length + 1));
    final source = wantNew ? fresh : familiar;
    var index = wantNew ? freshIndex : familiarIndex;
    while (index < source.length && !fits(source[index])) {
      index++;
    }
    if (wantNew) {
      freshIndex = index + 1;
    } else {
      familiarIndex = index + 1;
    }
    if (index >= source.length) {
      if (freshIndex >= fresh.length && familiarIndex >= familiar.length) {
        break;
      }
      continue;
    }
    final song = source[index];
    final key = artistKey(song['artist']);
    perArtistCount[key] = (perArtistCount[key] ?? 0) + 1;
    if (wantNew) newCount++;
    picked.add(song);
  }
  return spaceArtists(picked);
}

/// Reorders [songs] so the same artist doesn't play twice in a row, when
/// another song can go in between.
List<Map> spaceArtists(List<Map> songs) {
  final remaining = List<Map>.of(songs);
  final result = <Map>[];
  String? last;
  while (remaining.isNotEmpty) {
    final index = remaining.indexWhere((s) => artistKey(s['artist']) != last);
    final song = remaining.removeAt(index == -1 ? 0 : index);
    last = artistKey(song['artist']);
    result.add(song);
  }
  return result;
}
