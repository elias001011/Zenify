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

import 'package:musify/main.dart' show logger;
import 'package:musify/services/artist_service.dart';
import 'package:musify/services/proxy_manager.dart';
import 'package:musify/services/unavailable_songs.dart';
import 'package:musify/utilities/formatter.dart';

/// The search text for a song: its artist and title.
String replacementQuery(Map song) => [song['artist'], song['title']]
    .map((part) => part?.toString().trim() ?? '')
    .where((part) => part.isNotEmpty)
    .join(' ');

/// Another upload of [song] to take its place, or null when none is found.
/// YouTube Music is asked first, for the song of the same artist and title;
/// a plain YouTube search is the fallback. Results in [exclude], the ones
/// known to be unavailable and the song itself are never offered.
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
      return returnSongLayout(0, video);
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
      if (usable(video.id.value) && !video.isLive) {
        return returnSongLayout(0, video);
      }
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
