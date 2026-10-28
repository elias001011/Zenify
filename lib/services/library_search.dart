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

import 'package:musify/services/common_services.dart';
import 'package:musify/services/playlist_download_service.dart';
import 'package:musify/services/playlists_manager.dart';

/// What of the user's library matches a search.
typedef LibraryMatches = ({
  List<Map> artists,
  List<Map> playlists,
  List<Map> songs,
});

/// Searches the library by title (and artist, for songs). [offlineOnly]
/// keeps to what plays without a connection.
LibraryMatches searchLibrary(String query, {bool offlineOnly = false}) {
  final needle = query.trim().toLowerCase();
  bool matches(Object? value) =>
      needle.isNotEmpty &&
      (value?.toString().toLowerCase().contains(needle) ?? false);

  final offlinePlaylists = offlinePlaylistService.offlinePlaylists.value
      .whereType<Map>()
      .where((playlist) => !isArtistPlaylist(playlist));
  final addedIds = userPlaylists.value.toSet();

  final playlists = _uniqueByYtid([
    if (!offlineOnly) ...[
      ...getUserCustomPlaylists(),
      for (final folder in userPlaylistFolders.value)
        ...(folder['playlists'] as List? ?? const []).whereType<Map>(),
    ],
    ...offlinePlaylists,
    if (!offlineOnly) ...[
      ...getLikedPlaylistItems(),
      // Added YouTube playlists, as far as their details are known.
      ...onlinePlaylists.value.where((p) => addedIds.contains(p['ytid'])),
    ],
  ]).where((playlist) => matches(playlist['title'])).toList();

  final songs = searchLibrarySongs(query, offlineOnly: offlineOnly);

  final artists = getLikedArtistItems(offlineOnly: offlineOnly)
      .where((artist) => matches(artist['title']));

  return (artists: artists.toList(), playlists: playlists, songs: songs);
}

/// The library's songs whose title or artist matches [query].
List<Map> searchLibrarySongs(String query, {bool offlineOnly = false}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const [];
  bool matches(Object? value) =>
      value?.toString().toLowerCase().contains(needle) ?? false;
  return [
    for (final song in _librarySongs(offlineOnly))
      if (matches(song['title']) || matches(song['artist'])) song,
  ];
}

/// Every song of the library once: downloaded first, so a song plays from
/// its file wherever it shows.
List<Map> _librarySongs(bool offlineOnly) => _uniqueByYtid([
  ...userOfflineSongs.value.whereType<Map>(),
  if (!offlineOnly) ...[
    ...userLikedSongsList.value.whereType<Map>(),
    for (final playlist in getUserCustomPlaylists())
      ...(playlist['list'] as List? ?? const []).whereType<Map>(),
  ],
]);

/// The library's songs by YouTube id, to recognise them among online results.
Map<String, Map> librarySongsById() => {
  for (final song in _librarySongs(false))
    if (song['ytid']?.toString() case final id?) id: song,
};

/// Search results with what the library holds first: [library] matches, then
/// [online] results the library has under another title (shown as the
/// library's copy, from [known]), then the rest. Each part keeps to [limit].
List<Map> libraryFirst(
  List<Map> library,
  Iterable<dynamic> online, {
  Map<String, Map> known = const {},
  int limit = 15,
}) {
  final seen = {for (final item in library) item['ytid']?.toString()};
  final owned = <Map>[];
  final rest = <Map>[];
  for (final item in online.whereType<Map>()) {
    final id = item['ytid']?.toString();
    if (id != null && !seen.add(id)) continue;
    if (known[id] case final mine?) {
      owned.add(mine);
    } else {
      rest.add(item);
    }
  }
  return [
    ...library.take(limit),
    ...[...owned, ...rest].take(limit),
  ];
}

List<Map> _uniqueByYtid(Iterable<Map> items) {
  final seen = <String>{};
  return [
    for (final item in items)
      if (seen.add(item['ytid']?.toString() ?? '${item.hashCode}')) item,
  ];
}
