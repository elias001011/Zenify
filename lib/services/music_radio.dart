/*
 *     Copyright (C) 2025 Valeri Gokadze
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

import 'package:flutter/foundation.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/moods/moods_service.dart';
import 'package:musify/services/settings_manager.dart';

/// What follows a song, from YouTube Music's radio. The radio only holds
/// songs, so a seed that is no song (rain sounds, a long mix, an upload)
/// gets nothing from it, and every function here then falls back to the
/// YouTube related videos the app always used.
///
/// The Home's "recommended for you" is not here: it keeps its own sources.

({String seed, List<Map> songs})? _following;

/// Where the radios come from and what stands in when they have nothing.
@visibleForTesting
var radioOf = moodsService.radio;

@visibleForTesting
var relatedTo = getSimilarSong;

@visibleForTesting
var fallbackRecommendations = getRecommendedSongsForPlaylist;

@visibleForTesting
void forgetRadios() {
  _following = null;
  _playlistRadios.clear();
}

/// The next song for the automatic picker: the first song of the radio of
/// [songYtId] that is not in [excludedYtIds].
///
/// One radio is followed while it has songs left, as YouTube Music's autoplay
/// does, instead of asking for a new one at every song.
Future<Map<String, dynamic>?> pickNextSong(
  String songYtId, {
  Set<String> excludedYtIds = const {},
}) async {
  if (!offlineMode.value) {
    Map? next(List<Map> songs) =>
        songs.where((s) => !excludedYtIds.contains(s['ytid'])).firstOrNull;

    final current = _following;
    final continues =
        current != null &&
        (current.seed == songYtId ||
            current.songs.any((song) => song['ytid'] == songYtId));
    var pick = continues ? next(current.songs) : null;
    if (pick == null) {
      final songs = await radioOf(songYtId);
      _following = (seed: songYtId, songs: songs);
      pick = next(songs);
    }
    if (pick != null) return Map<String, dynamic>.from(pick);
  }
  return relatedTo(songYtId, excludedYtIds: excludedYtIds);
}

/// Songs for the end of a playlist's page: the radios of a few of its songs
/// merged, those near the top of a radio first.
Future<List> getPlaylistRecommendations(
  String playlistId,
  List playlistSongs,
) async {
  final inPlaylist = {
    for (final song in playlistSongs.whereType<Map>()) song['ytid']?.toString(),
  };
  final cached = _playlistRadios[playlistId]?.where(
    (song) => !inPlaylist.contains(song['ytid']),
  );
  if (cached != null && cached.isNotEmpty) return cached.toList();

  if (!offlineMode.value) {
    final seeds = sampleSeedSongs(playlistSongs, 5);
    final radios = await Future.wait([
      for (final seed in seeds) radioOf(seed['ytid'].toString()),
    ]);
    final scores = <String, double>{};
    final songs = <String, Map>{};
    for (final (seedIndex, radio) in radios.indexed) {
      final recency = 1.0 - seedIndex / radios.length;
      for (final (position, song) in radio.take(10).indexed) {
        final id = song['ytid'].toString();
        if (inPlaylist.contains(id)) continue;
        scores[id] = (scores[id] ?? 0) + (1 - position / 10) * recency;
        songs[id] = song;
      }
    }
    final ranked = (scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value)));
    final picks = [for (final e in ranked.take(15)) songs[e.key]!];
    if (picks.isNotEmpty) return _playlistRadios[playlistId] = picks;
  }
  return fallbackRecommendations(playlistId, playlistSongs);
}

/// In-memory, like the related-videos recommendations, cleared on restart.
final _playlistRadios = <String, List<Map>>{};
