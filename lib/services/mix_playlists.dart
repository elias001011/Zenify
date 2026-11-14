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
import 'package:musify/services/data_manager.dart';

/// The custom playlists that play with the Mix, by id. Zenify's own: a
/// backup without it restores as before.
final mixPlaylists = ValueNotifier<Set<String>>(_stored());

Set<String> _stored() {
  final stored = Hive.box('settings').get('mixPlaylists');
  return stored is List ? {for (final id in stored) id.toString()} : {};
}

/// Reads the playlists again, after a restore or a sync.
void reloadMixPlaylists() => mixPlaylists.value = _stored();

void setPlaylistMix(String id, {required bool on}) {
  final next = {...mixPlaylists.value};
  if (!(on ? next.add(id) : next.remove(id))) return;
  mixPlaylists.value = next;
  addOrUpdateData<List<String>>('settings', 'mixPlaylists', next.toList());
}
