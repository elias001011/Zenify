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

import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/moods/mix_engine.dart';

/// What the user told the Moods in their tuning: genres left out, artists
/// never suggested and how much they want to discover.
///
/// Kept in the user's library, so backups, restores and Local Sync carry it.
/// A library without it (one from Musify, or from before the Moods) reads as
/// the defaults: nothing left out, a balanced discovery.
class MoodsTuning {
  const MoodsTuning({
    this.excludedGenres = const {},
    this.blockedArtists = const {},
    this.discovery = Discovery.balanced,
  });

  factory MoodsTuning.fromStorage(Object? raw) {
    if (raw is! Map) return const MoodsTuning();
    Set<String> strings(Object? value) =>
        value is List ? {for (final e in value) e.toString()} : const {};
    return MoodsTuning(
      excludedGenres: strings(raw['excludedGenres']),
      blockedArtists: strings(raw['blockedArtists']),
      discovery: Discovery.values.firstWhere(
        (d) => d.name == raw['discovery'] && d != Discovery.onlyNew,
        orElse: () => Discovery.balanced,
      ),
    );
  }

  static const storageKey = 'moodsTuning';

  /// YouTube Music genre titles, in English (`Jazz`, `Samba & pagode`).
  final Set<String> excludedGenres;

  /// Artist keys (see `artistKey`).
  final Set<String> blockedArtists;

  final Discovery discovery;

  bool get isDefault =>
      excludedGenres.isEmpty &&
      blockedArtists.isEmpty &&
      discovery == Discovery.balanced;

  MoodsTuning copyWith({
    Set<String>? excludedGenres,
    Set<String>? blockedArtists,
    Discovery? discovery,
  }) => MoodsTuning(
    excludedGenres: excludedGenres ?? this.excludedGenres,
    blockedArtists: blockedArtists ?? this.blockedArtists,
    discovery: discovery ?? this.discovery,
  );

  Map<String, dynamic> toStorage() => {
    'excludedGenres': excludedGenres.toList()..sort(),
    'blockedArtists': blockedArtists.toList()..sort(),
    'discovery': discovery.name,
  };
}

final moodsTuning = ValueNotifier<MoodsTuning>(
  MoodsTuning.fromStorage(Hive.box('user').get(MoodsTuning.storageKey)),
);

/// Zenify playlists the user saved to the library, by id (`zenify:daily`).
/// In the library like the tuning, and just as optional.
final savedZenifyPlaylists = ValueNotifier<List<String>>(_readSaved());

const savedZenifyPlaylistsKey = 'savedZenifyPlaylists';

List<String> _readSaved() {
  final raw = Hive.box('user').get(savedZenifyPlaylistsKey);
  return raw is List ? [for (final id in raw) id.toString()] : [];
}

Future<void> setMoodsTuning(MoodsTuning tuning) async {
  moodsTuning.value = tuning;
  final box = Hive.box('user');
  // The defaults leave nothing behind, so a library stays as Musify knows it.
  tuning.isDefault
      ? await box.delete(MoodsTuning.storageKey)
      : await box.put(MoodsTuning.storageKey, tuning.toStorage());
}

Future<void> setZenifyPlaylistSaved(String id, bool saved) async {
  final ids = List<String>.of(savedZenifyPlaylists.value)..remove(id);
  if (saved) ids.insert(0, id);
  savedZenifyPlaylists.value = ids;
  final box = Hive.box('user');
  ids.isEmpty
      ? await box.delete(savedZenifyPlaylistsKey)
      : await box.put(savedZenifyPlaylistsKey, ids);
}

/// After a restore or a Local Sync merge rewrote the library.
void reloadMoodsFromStorage() {
  moodsTuning.value = MoodsTuning.fromStorage(
    Hive.box('user').get(MoodsTuning.storageKey),
  );
  savedZenifyPlaylists.value = _readSaved();
}
