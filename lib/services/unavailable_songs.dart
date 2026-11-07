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

import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';

/// Songs YouTube itself reports as unplayable (removed, private, not
/// available), learnt when a download fails that way and forgotten when a
/// download or a playback works. A network failure is never recorded here.
///
/// Kept on this device only: what is unavailable here may play elsewhere.
class UnavailableSongs {
  UnavailableSongs._();

  static const _idsKey = 'unavailableSongs';
  static const _dismissedKey = 'unavailableDismissed';
  static const _maxIds = 2000;
  static const _writeDelay = Duration(seconds: 1);

  Timer? _writeTimer;

  late final ids = ValueNotifier<Set<String>>(_loadIds());

  // Keeping the record is a convenience: without the box, nothing is kept.
  Box? get _box =>
      Hive.isBoxOpen('userNoBackup') ? Hive.box('userNoBackup') : null;

  Set<String> _loadIds() {
    final raw = _box?.get(_idsKey);
    return raw is List ? {for (final id in raw) id.toString()} : {};
  }

  bool contains(Object? ytid) => ids.value.contains(ytid);

  void markUnavailable(String ytid) {
    if (ids.value.contains(ytid)) return;
    final next = {...ids.value, ytid};
    // Sets keep their insertion order: the oldest go first.
    while (next.length > _maxIds) {
      next.remove(next.first);
    }
    _setIds(next);
  }

  void markAvailable(String ytid) {
    if (!ids.value.contains(ytid)) return;
    _setIds({...ids.value}..remove(ytid));
  }

  void _setIds(Set<String> next) {
    ids.value = next;
    // A failing playlist flags many songs: one write for the burst.
    if (persist) _writeTimer ??= Timer(_writeDelay, flush);
  }

  /// Writes the record now.
  void flush() {
    _writeTimer?.cancel();
    _writeTimer = null;
    _box?.put(_idsKey, ids.value.toList());
  }

  final _dismissed = <String, Set<String>>{};

  /// The songs of [playlistId] whose notice the user closed.
  Set<String> dismissed(String playlistId) => _dismissed[playlistId] ??= () {
    final raw = _box?.get(_dismissedKey);
    final list = raw is Map ? raw[playlistId] : null;
    return list is List ? {for (final id in list) id.toString()} : <String>{};
  }();

  /// Stops telling about [songs] in [playlistId]; one that fails later, and
  /// is not among them, brings the notice back.
  void dismiss(String playlistId, Iterable<String> songs) {
    final dismissed = _dismissed[playlistId] = {
      ...this.dismissed(playlistId),
      ...songs,
    };
    if (persist) {
      // Merged with the file: playlists not opened this session keep theirs.
      final stored = _box?.get(_dismissedKey);
      _box?.put(_dismissedKey, {
        if (stored is Map)
          for (final entry in stored.entries) entry.key.toString(): entry.value,
        playlistId: dismissed.toList(),
      });
    }
    // The notice reads this together with the ids, so it follows them.
    ids.value = {...ids.value};
  }

  /// Whether what is learnt is written to the device. Off in tests that run
  /// under a fake clock, where writes to the box never settle.
  @visibleForTesting
  var persist = true;

  @visibleForTesting
  void reset() {
    _dismissed.clear();
    ids.value = {};
  }
}

final unavailableSongs = UnavailableSongs._();
