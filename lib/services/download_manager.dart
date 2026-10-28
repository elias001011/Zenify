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

import 'dart:async';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

enum DownloadStatus { downloading, done, failed }

enum DownloadFailure { unavailable, network, other }

/// One song download, as shown in the Downloads tab.
class DownloadEntry {
  DownloadEntry({
    required this.song,
    required this.status,
    required this.time,
    this.failure,
  });

  factory DownloadEntry.fromMap(Map map) => DownloadEntry(
    song: Map<String, dynamic>.from(map['song'] as Map),
    status: DownloadStatus.values.byName(map['status'] as String),
    time: DateTime.fromMillisecondsSinceEpoch(map['time'] as int),
    failure: map['failure'] == null
        ? null
        : DownloadFailure.values.byName(map['failure'] as String),
  );

  final Map<String, dynamic> song;
  DownloadStatus status;
  DateTime time;
  DownloadFailure? failure;

  /// 0 to 1 while downloading; null when the size is unknown.
  final progress = ValueNotifier<double?>(null);

  String get ytid => song['ytid'].toString();

  Map<String, dynamic> toMap() => {
    'song': song,
    'status': status.name,
    'time': time.millisecondsSinceEpoch,
    'failure': failure?.name,
  };
}

/// Every song download, current and past, so the Downloads tab can show what
/// is downloading, what finished and what failed, and retry failures.
///
/// Downloads report here from `makeSongOffline`, which every download path
/// (single songs, playlists, the player, shortcuts) goes through.
class DownloadManager {
  DownloadManager._();

  static final instance = DownloadManager._();

  static const _storageKey = 'downloadHistory';
  static const _maxHistory = 200;
  static const _persistDelay = Duration(seconds: 1);

  /// Newest first: downloads in progress plus the last [_maxHistory] others.
  late final entries = ValueNotifier<List<DownloadEntry>>(_load());
  Timer? _persistTimer;

  static List<DownloadEntry> _load() {
    try {
      final raw = Hive.box('userNoBackup').get(_storageKey);
      if (raw is List) {
        return [
          for (final item in raw)
            if (item is Map) DownloadEntry.fromMap(item),
        ];
      }
    } catch (_) {
      // A broken history is dropped, not fatal.
    }
    return [];
  }

  List<DownloadEntry> get active => entries.value
      .where((entry) => entry.status == DownloadStatus.downloading)
      .toList();

  DownloadEntry started(Map song) {
    final entry = DownloadEntry(
      song: Map<String, dynamic>.from(song),
      status: DownloadStatus.downloading,
      time: DateTime.now(),
    );
    entries.value = [
      entry,
      ...entries.value.where((other) => other.ytid != entry.ytid),
    ];
    return entry;
  }

  void finished(DownloadEntry entry) => _settle(entry, DownloadStatus.done);

  void failed(DownloadEntry entry, Object? error) {
    entry.failure = failureFor(error);
    _settle(entry, DownloadStatus.failed);
  }

  void _settle(DownloadEntry entry, DownloadStatus status) {
    entry
      ..status = status
      ..time = DateTime.now()
      ..progress.value = null;
    // A playlist download settles many songs; keep the history bounded.
    var kept = 0;
    entries.value = [
      for (final other in entries.value)
        if (other.status == DownloadStatus.downloading || kept++ < _maxHistory)
          other,
    ];
    _schedulePersist();
  }

  void clearHistory() {
    entries.value = active;
    _schedulePersist();
  }

  /// Batches the writes of a playlist download into one per [_persistDelay].
  void _schedulePersist() => _persistTimer ??= Timer(_persistDelay, flush);

  /// Writes the history now.
  void flush() {
    _persistTimer?.cancel();
    _persistTimer = null;
    final history = [
      for (final entry in entries.value)
        if (entry.status != DownloadStatus.downloading) entry.toMap(),
    ];
    Hive.box('userNoBackup').put(_storageKey, history);
  }

  @visibleForTesting
  static DownloadFailure failureFor(Object? error) {
    if (error == null) return DownloadFailure.unavailable;
    if (error is SocketException ||
        error is HttpException ||
        error is http.ClientException) {
      return DownloadFailure.network;
    }
    return DownloadFailure.other;
  }
}
