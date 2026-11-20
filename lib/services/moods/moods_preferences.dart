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

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';

/// Zenify playlists the user saved to the library, by id (`zenify:daily`).
/// Kept in the library and synchronized between devices.
final savedZenifyPlaylists = ValueNotifier<List<String>>(_readSaved());

const savedZenifyPlaylistsKey = 'savedZenifyPlaylists';

List<String> _readSaved() {
  final raw = Hive.box('user').get(savedZenifyPlaylistsKey);
  return raw is List ? [for (final id in raw) id.toString()] : [];
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
  final saved = _readSaved();
  if (!listEquals(saved, savedZenifyPlaylists.value)) {
    savedZenifyPlaylists.value = saved;
  }
}
