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
import 'package:musify/services/settings_manager.dart';
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

  // Very short names ("U2", "AC/DC") are still the credit to look for.
  var artist = _words(song['artist'], minLength: 3);
  if (artist.isEmpty) artist = _words(song['artist']);
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
  // A title alone, with no artist and no length to check, proves nothing.
  if (artist.isEmpty && !(length is num && length > 0)) return false;
  return true;
}

/// How many searches in a row may fail before the others are not tried.
const _failuresBeforeGivingUp = 3;

/// Neither search could be made at all (no connection, YouTube refusing): not
/// the same as a search that found nothing.
class ReplacementSearchFailed implements Exception {
  const ReplacementSearchFailed();
}

/// Another upload of [song] to take its place, or null when none is found.
/// YouTube Music is asked first, for the song of the same artist and title;
/// a plain YouTube search is the fallback. What is offered must be the same
/// recording ([isSameRecording]); results in [exclude], the ones known to be
/// unavailable and the song itself are never offered. Throws
/// [ReplacementSearchFailed] when no search could be made.
Future<Map<String, dynamic>?> findReplacementSong(
  Map song, {
  Set<String> exclude = const {},
}) => _find(song, exclude, youtubeMusic: true);

/// The same, with the plain YouTube search only: for what YouTube Music was
/// already asked and did not find.
Future<Map<String, dynamic>?> findOnYoutube(
  Map song, {
  Set<String> exclude = const {},
}) => _find(song, exclude, youtubeMusic: false);

Future<Map<String, dynamic>?> _find(
  Map song,
  Set<String> exclude, {
  required bool youtubeMusic,
}) async {
  final query = replacementQuery(song);
  if (query.isEmpty) return null;
  final skip = {...exclude, song['ytid'].toString()};
  bool usable(String? id) =>
      id != null && !skip.contains(id) && !unavailableSongs.contains(id);
  var searched = false;

  if (youtubeMusic) {
    try {
      final video = await ytMusicClient.music.searchSong(
        query,
        expectedArtist: song['artist']?.toString(),
        expectedTitle: song['title']?.toString(),
      );
      searched = true;
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
  }

  try {
    final results = await ytClient.search.search(query);
    searched = true;
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
  if (!searched) throw const ReplacementSearchFailed();
  return null;
}

/// Where the replacements come from and how they are downloaded.
@visibleForTesting
var findReplacement = findReplacementSong;

@visibleForTesting
var findFallback = findOnYoutube;

@visibleForTesting
var downloadReplacement = makeSongOffline;

/// Tells the playlist pages that are open that songs were swapped in storage.
final replacedSongs = ValueNotifier<int>(0);

/// What a swap would do, for the person to see before it is made: the
/// unavailable [songs] searched for, what was [found] for each (by the
/// ytid of the song to leave) and the playlists it would touch.
class ReplacementPlan {
  const ReplacementPlan({
    required this.songs,
    required this.found,
    required this.playlistIds,
    this.held = const {},
    this.notSearched = const {},
  });

  final List<Map> songs;
  final Map<String, Map> found;
  final Set<String> playlistIds;

  /// Every song those playlists hold: none of them is a replacement.
  final Set<String> held;

  /// Songs whose search could not be made, as opposed to finding nothing.
  final Set<String> notSearched;
}

/// Whether a replacement search or its review is under way: the button that
/// started it must outlive the downloads that begin meanwhile.
final replacing = ValueNotifier<bool>(false);

/// What decides [canOfferReplacement]; rebuild when any of it changes.
final replacementOffer = Listenable.merge([
  DownloadManager.instance.idle,
  replacing,
  offlineMode,
]);

/// Whether the notices and buttons to replace unavailable songs show: online,
/// and once every download is over (a song may be queued by another playlist
/// and still fail), or while a replacement is under way.
bool get canOfferReplacement =>
    !offlineMode.value &&
    (DownloadManager.instance.idle.value || replacing.value);

/// Searches replacements for [songs], unavailable on YouTube, among those a
/// playlist you made holds (only [playlistId] when given) and still flagged.
/// Nothing is changed: see [applyReplacements]. Throws
/// [ReplacementSearchFailed] when no search could be made.
Future<ReplacementPlan> planReplacements(
  Iterable<Map> songs, {
  String? playlistId,
}) async {
  final playlists = [
    for (final playlist in getUserCustomPlaylists())
      if (playlistId == null || playlist['ytid']?.toString() == playlistId)
        playlist,
  ];
  final taken = songIdsOf(playlists);

  final searched = <Map>[];
  for (final song in songs) {
    final id = song['ytid'].toString();
    if (!taken.contains(id) || !unavailableSongs.contains(id)) continue;
    // A song kept twice is searched, and listed, once.
    if (searched.every((s) => s['ytid'].toString() != id)) searched.add(song);
  }
  final result = await _searchEach(searched, findReplacement, held: taken);
  // Every search failed: there is no telling whether replacements exist.
  if (searched.isNotEmpty && result.notSearched.length == searched.length) {
    throw const ReplacementSearchFailed();
  }
  return ReplacementPlan(
    songs: searched,
    found: result.found,
    playlistIds: {for (final p in playlists) p['ytid'].toString()},
    held: taken,
    notSearched: result.notSearched,
  );
}

typedef _Finder = Future<Map<String, dynamic>?> Function(
  Map song, {
  Set<String> exclude,
});

/// Looks for each of [songs] with [find], one after another. A match is never
/// offered twice, nor a song of [held]. Searches that keep failing (YouTube
/// limiting this device) are not pressed on: the rest are left for the
/// person to try by hand. Returns the matches by the id of the song they
/// are for, and the songs whose search could not be made, as opposed to
/// those that found nothing.
Future<({Map<String, Map> found, Set<String> notSearched})> _searchEach(
  Iterable<Map> songs,
  _Finder find, {
  Set<String> held = const {},
  VoidCallback? onSearched,
}) async {
  final found = <String, Map>{};
  final notSearched = <String>{};
  var failures = 0;
  for (final song in songs) {
    final id = song['ytid'].toString();
    if (failures >= _failuresBeforeGivingUp) {
      notSearched.add(id);
    } else {
      try {
        final match = await find(
          song,
          exclude: {
            ...held,
            for (final f in found.values) f['ytid'].toString(),
          },
        );
        if (match != null) found[id] = match;
        failures = 0;
      } on ReplacementSearchFailed {
        notSearched.add(id);
        failures++;
      }
    }
    onSearched?.call();
  }
  return (found: found, notSearched: notSearched);
}

/// Looks on YouTube for the songs of an import that YouTube Music did not
/// find (asking YouTube Music again would only fail again). A match must pass
/// [isSameRecording]. [held] are the songs the playlist already has.
Future<({Map<String, Map> found, Set<String> notSearched})> searchOnYoutube(
  List<Map> songs, {
  Set<String> held = const {},
  VoidCallback? onSearched,
}) => _searchEach(songs, findFallback, held: held, onSearched: onSearched);

/// Swaps in [plan]'s playlists the songs of [swaps] (the ytid to leave and
/// the song to take its place) and starts downloading the replacements.
/// Every playlist that holds a song gets the same replacement. A song that
/// plays after all stays.
///
/// A song no playlist or liked list of yours holds any more is no longer
/// unavailable for the app: it leaves the record and the Downloads tab,
/// wherever the swap was asked. Returns how many songs were swapped.
Future<int> applyReplacements(
  ReplacementPlan plan,
  Map<String, Map> swaps,
) async {
  // The searching, and the person's reading, took a while: a song may have
  // played since, and the playlists may have been edited, which replaces
  // their maps. What is swapped is read again now, and only then.
  final live = {
    for (final entry in swaps.entries)
      // Never a song for itself: it would only remove it.
      if (unavailableSongs.contains(entry.key) &&
          entry.value['ytid'].toString() != entry.key)
        entry.key: entry.value,
  };
  final applied = <String>{};
  for (final playlist in getUserCustomPlaylists()) {
    if (!plan.playlistIds.contains(playlist['ytid'].toString())) continue;
    final here = songIdsOf([playlist]);
    applied.addAll(
      replaceSongsInPlaylist(playlist, {
        for (final entry in live.entries)
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

  unawaited(
    DownloadManager.instance
        .inRun(
          () => Future.wait([
            for (final id in applied)
              Future.sync(() => downloadReplacement(live[id])),
          ]),
        )
        .then<void>((_) {}, onError: (Object _) {}),
  );
  replacedSongs.value++;
  return applied.length;
}

/// Songs for [query], for choosing a replacement by hand.
Future<List<Map>> searchReplacementCandidates(String query) async =>
    (await fetchSongsList(query)).whereType<Map>().toList();
