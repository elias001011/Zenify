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

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/services/artist_service.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/download_manager.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/proxy_manager.dart';
import 'package:musify/services/unavailable_songs.dart';
import 'package:musify/utilities/formatter.dart';

/// The search text for a song: its artist and title.
String replacementQuery(Map song) => [song['artist'], song['title']]
    .map((part) => part?.toString().trim() ?? '')
    .where((part) => part.isNotEmpty)
    .join(' ');

final _notWord = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

Set<String> _words(Object? text, {int minLength = 1}) => {
  for (final word in (text?.toString() ?? '').toLowerCase().split(_notWord))
    if (word.length >= minLength) word,
};

/// Whether [candidate] is the same recording as [song]: its title says the
/// same and no more (the artist's name apart), its own artist or channel is
/// the song's artist, and it is about as long. A mention of the artist in the
/// title does not count as a credit, and "(Queen cover)" or "Remix" are more
/// than the title says. A wrong swap is saved for good, so when in doubt the
/// answer is no. [candidate] has a cleaned title, as the layouts give.
bool isSameRecording(Map song, Map candidate) {
  final title = _words(song['title']);
  if (title.isEmpty) return false;
  final artistWords = _words(song['artist']);
  final candidateTitle = _words(candidate['title']);
  if (!candidateTitle.containsAll(title)) return false;
  if (candidateTitle.difference(title).difference(artistWords).isNotEmpty) {
    return false;
  }

  final artist = _words(song['artist'], minLength: 3);
  if (artist.isNotEmpty) {
    final credited = {
      ..._words(candidate['artist']),
      ..._words(candidate['videoAuthor']),
    };
    if (artist.intersection(credited).isEmpty) return false;
  }

  final length = song['duration'];
  final candidateLength = candidate['duration'];
  if (length is num && candidateLength is num && length > 0) {
    if ((length - candidateLength).abs() > max(10, length * 0.1)) return false;
  }
  return true;
}

/// Another upload of [song] to take its place, or null when none is found.
/// YouTube Music is asked first, for the song of the same artist and title;
/// a plain YouTube search is the fallback. What is offered must be the same
/// recording ([isSameRecording]); results in [exclude], the ones known to be
/// unavailable and the song itself are never offered.
Future<Map<String, dynamic>?> findReplacementSong(
  Map song, {
  Set<String> exclude = const {},
}) async {
  final query = replacementQuery(song);
  if (query.isEmpty) return null;
  final skip = {...exclude, song['ytid'].toString()};
  bool usable(String? id) =>
      id != null && !skip.contains(id) && !unavailableSongs.contains(id);

  try {
    final video = await ytMusicClient.music.searchSong(
      query,
      expectedArtist: song['artist']?.toString(),
      expectedTitle: song['title']?.toString(),
    );
    if (video != null && usable(video.id.value)) {
      final candidate = returnSongLayout(0, video);
      if (isSameRecording(song, candidate)) return candidate;
    }
  } catch (e, stackTrace) {
    logger.log(
      'YouTube Music search for a replacement failed',
      error: e,
      stackTrace: stackTrace,
    );
  }

  try {
    final results = await ytClient.search.search(query);
    for (final video in results) {
      if (!usable(video.id.value) || video.isLive) continue;
      final candidate = returnSongLayout(0, video);
      if (isSameRecording(song, candidate)) return candidate;
    }
  } catch (e, stackTrace) {
    logger.log(
      'YouTube search for a replacement failed',
      error: e,
      stackTrace: stackTrace,
    );
  }
  return null;
}

/// Where the replacements come from and how they are downloaded.
@visibleForTesting
var findReplacement = findReplacementSong;

@visibleForTesting
var downloadReplacement = makeSongOffline;

/// Tells the playlist pages that are open that songs were swapped in storage.
final replacedSongs = ValueNotifier<int>(0);

/// Swaps [songs], unavailable on YouTube, for other uploads in the
/// playlists you made, and starts downloading the replacements. Every
/// playlist that holds a song gets the same replacement, unless [playlistId]
/// limits it to one. A song nothing is found for stays where it is, and so
/// does one that plays after all.
///
/// A song no playlist or liked list of yours holds any more is no longer
/// unavailable for the app: it leaves the record and the Downloads tab,
/// wherever the swap was asked. Returns how many songs were swapped.
Future<int> replaceUnavailableSongs(
  Iterable<Map> songs, {
  String? playlistId,
}) async {
  final playlists = [
    for (final playlist in getUserCustomPlaylists())
      if (playlistId == null || playlist['ytid']?.toString() == playlistId)
        playlist,
  ];
  final taken = songIdsOf(playlists);

  final found = <String, Map>{};
  for (final song in songs) {
    final id = song['ytid'].toString();
    if (!taken.contains(id) || !unavailableSongs.contains(id)) continue;
    final replacement = await findReplacement(
      song,
      exclude: {...taken, for (final r in found.values) r['ytid'].toString()},
    );
    if (replacement != null) found[id] = replacement;
  }

  // The searching took a while: a song may have played since, and the
  // playlists may have been edited, which replaces their maps. What is
  // swapped is read again now, and only then.
  final swaps = {
    for (final entry in found.entries)
      if (unavailableSongs.contains(entry.key)) entry.key: entry.value,
  };
  final scope = {for (final playlist in playlists) playlist['ytid'].toString()};
  final applied = <String>{};
  for (final playlist in getUserCustomPlaylists()) {
    if (!scope.contains(playlist['ytid'].toString())) continue;
    final here = songIdsOf([playlist]);
    applied.addAll(
      replaceSongsInPlaylist(playlist, {
        for (final entry in swaps.entries)
          if (here.contains(entry.key)) entry.key: entry.value,
      }),
    );
  }
  if (applied.isEmpty) return 0;

  final stillHeld = {
    ...songIdsOf(getUserCustomPlaylists()),
    ...songIdsOf(userLikedPlaylists.value.whereType<Map>()),
    for (final song in userLikedSongsList.value.whereType<Map>())
      song['ytid'].toString(),
  };
  final settled = applied.where((id) => !stillHeld.contains(id)).toList()
    ..forEach(unavailableSongs.markAvailable);
  DownloadManager.instance.forget(settled);

  for (final id in applied) {
    unawaited(downloadReplacement(swaps[id]));
  }
  replacedSongs.value++;
  return applied.length;
}
