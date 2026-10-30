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

/// Longer than this is a mix, a compilation or "1 hour of…", not a song.
const maxSongSeconds = 12 * 60;

final _notASong = RegExp(
  r'\b(rain|chuva|thunder|trovão|white noise|ruído branco|brown noise|'
  'pink noise|sleep sounds?|sons? para dormir|nature sounds?|'
  'sons? da natureza|ocean waves|ondas do mar|asmr|24/7|'
  r'\d+\s*(hours?|horas?|hrs?)|full album|álbum completo|album completo|'
  r'compilation|coletânea|non-?stop|mixtape|dj set)\b',
  caseSensitive: false,
  unicode: true,
);

/// Whether [song] (a song map) looks like a song: short enough and not one
/// of the sounds and mixes people play that say nothing about their taste.
bool looksLikeSong(Map song) {
  final seconds = song['duration'];
  if (seconds is num && seconds > maxSongSeconds) return false;
  if (song['isLive'] == true) return false;
  return !_notASong.hasMatch('${song['title'] ?? ''} ${song['artist'] ?? ''}');
}

/// One artist name, comparable across spellings: "Seu Jorge & Ana Carolina"
/// and "seu jorge" share a key. Only the first credited artist counts.
String artistKey(Object? artist) {
  final name = (artist ?? '').toString().toLowerCase().split(
    RegExp(r',|&| feat\.? | ft\.? | x | e | and |\|'),
  )[0];
  return name.replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
}

/// How much a source says about the user's taste right now.
const _recapWeight = 1.0;
const _recentWeight = 0.6;
const _likedWeight = 0.5;
const _keptWeight = 0.2;

/// What the Moods know of the user's taste. It is worked out from the library
/// every time and never stored: liking a song, keeping it in a playlist or
/// playing it is how the user teaches the Moods.
class Taste {
  const Taste({
    this.seeds = const [],
    this.artists = const {},
    this.artistNames = const {},
    this.known = const {},
  });

  /// From the library. [recap] holds the songs of each recap month, the
  /// current one first; [recentlyPlayed] and [liked] are newest first.
  /// Songs by [blockedArtists] (keys) are left out entirely.
  factory Taste.of({
    List<Map> recap = const [],
    List recentlyPlayed = const [],
    List liked = const [],
    List kept = const [],
    Iterable<String> likedArtists = const [],
    Set<String> blockedArtists = const {},
    DateTime? now,
  }) {
    final today = now ?? DateTime.now();
    final weights = <String, double>{};
    final songs = <String, Map>{};
    final known = <String>{};

    void add(Object? raw, double weight) {
      if (raw is! Map) return;
      final id = raw['ytid']?.toString() ?? '';
      if (id.isEmpty) return;
      known.add(id);
      if (weight <= 0 ||
          !looksLikeSong(raw) ||
          blockedArtists.contains(artistKey(raw['artist']))) {
        return;
      }
      songs.putIfAbsent(id, () => raw);
      weights[id] = (weights[id] ?? 0) + weight;
    }

    // Time listened, halving with every month back; what was played this
    // week counts once and a half.
    final recapScores = <String, double>{};
    final recapSongs = <String, Map>{};
    for (var monthsAgo = 0; monthsAgo < recap.length; monthsAgo++) {
      for (final entry in recap[monthsAgo].values.whereType<Map>()) {
        final id = entry['ytid']?.toString() ?? '';
        if (id.isEmpty) continue;
        // Hours of rain would flatten every real song next to them.
        if (!looksLikeSong(entry)) {
          known.add(id);
          continue;
        }
        final seconds = entry['seconds'];
        var score =
            (seconds is num ? seconds.toDouble() : 0) / pow(2, monthsAgo);
        final last = DateTime.tryParse('${entry['lastPlayed']}');
        if (last != null && today.difference(last).inDays < 7) score *= 1.5;
        recapScores[id] = (recapScores[id] ?? 0) + score;
        recapSongs.putIfAbsent(id, () => entry);
      }
    }
    final topRecap = recapScores.values.fold<double>(0, max);
    for (final e in recapScores.entries) {
      add(recapSongs[e.key], _recapWeight * e.value / topRecap);
    }
    for (var i = 0; i < recentlyPlayed.length; i++) {
      add(recentlyPlayed[i], _recentWeight * (1 - i / recentlyPlayed.length));
    }
    // An old like still says something, a new one says more.
    for (var i = 0; i < liked.length; i++) {
      add(liked[i], _likedWeight * (1 - 0.7 * i / liked.length));
    }
    for (final song in kept) {
      add(song, _keptWeight);
    }

    final ranked = weights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final artists = <String, double>{};
    final names = <String, String>{};
    for (final e in ranked) {
      final song = songs[e.key]!;
      final key = artistKey(song['artist']);
      if (key.isEmpty) continue;
      artists[key] = (artists[key] ?? 0) + e.value;
      names.putIfAbsent(key, () => song['artist'].toString());
    }
    for (final name in likedArtists) {
      final key = artistKey(name);
      if (key.isEmpty || blockedArtists.contains(key)) continue;
      artists[key] = (artists[key] ?? 0) + 1;
      names.putIfAbsent(key, () => name);
    }
    final topArtist = artists.values.fold<double>(0, max);

    return Taste(
      seeds: [for (final e in ranked) (song: songs[e.key]!, weight: e.value)],
      artists: {for (final e in artists.entries) e.key: e.value / topArtist},
      artistNames: names,
      known: known,
    );
  }

  /// Songs to start from, strongest first.
  final List<({Map song, double weight})> seeds;

  /// How much the user listens to each artist, by [artistKey], from 0 to 1.
  final Map<String, double> artists;

  /// A display name for each artist key.
  final Map<String, String> artistNames;

  /// Songs the user already knows: heard, liked or kept.
  final Set<String> known;

  bool get isEmpty => seeds.isEmpty;

  double affinity(Map song) => artists[artistKey(song['artist'])] ?? 0;
}
