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
import 'dart:collection';
import 'dart:io';

import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/clients.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/services/unavailable_songs.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

enum DownloadStatus { queued, downloading, done, failed }

enum DownloadFailure { unavailable, network, other }

/// Thrown into a download that was told to stop.
class DownloadStopped implements Exception {
  const DownloadStopped();
}

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

/// Writes the files of [song] and records it as offline, reporting its
/// progress from 0 to 1. Throws when the song cannot be saved. It must end on
/// its own (a stalled transfer fails): the manager waits for it, because
/// letting go of one still writing would let the next try write the same
/// file.
typedef SongSaver = Future<void> Function(
  Map<String, dynamic> song,
  void Function(double),
);

/// Every song download, current and past, so the Downloads tab can show what
/// waits, what downloads, what finished and what failed, and retry failures.
///
/// All downloads (single songs, playlists, the player, shortcuts, retries)
/// go through [download]: one download per song at a time, and a few songs
/// at once however many playlists are downloading.
class DownloadManager {
  DownloadManager._();

  var _watchingOffline = false;

  // Offline mode keeps the app off the network: what is downloading stops.
  // Watched from the first download, when the settings are open.
  void _watchOffline() {
    if (_watchingOffline) return;
    _watchingOffline = true;
    offlineMode.addListener(() {
      if (offlineMode.value) unawaited(stopAll());
    });
  }

  static final instance = DownloadManager._();

  static const maxConcurrent = 3;
  static const _storageKey = 'downloadHistory';
  static const _maxHistory = 200;
  static const _persistDelay = Duration(seconds: 1);

  /// Newest first: queued and running downloads plus the last [_maxHistory]
  /// others.
  late final entries = ValueNotifier<List<DownloadEntry>>(_load());
  Timer? _persistTimer;
  final _inFlight = <String, _Request>{};

  /// Whether nothing is queued or downloading, for a moment longer than the
  /// last download: playlists start one after the other, and what is told at
  /// the end must not come in between. Notices about failures wait for it.
  final idle = ValueNotifier<bool>(true);

  /// What failed since the last time everything was idle, told once when it
  /// is again, whichever playlists the songs came from.
  final batch = ValueNotifier<DownloadBatch?>(null);

  @visibleForTesting
  var idleMargin = const Duration(seconds: 3);

  /// Whether the history is written to the device; off in tests that run
  /// under a fake clock.
  @visibleForTesting
  var persist = true;

  Timer? _idleTimer;
  final _runs = <DownloadRun>{};
  // The songs that failed since everything was last idle, by ytid, and
  // whether each is unavailable; one that later succeeds is not told.
  final _batchFailed = <String, bool>{};
  var _batches = 0;
  var _historyEpoch = 0;
  var _stopEpoch = 0;
  final _waiting = Queue<Completer<void>>();
  var _running = 0;

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

  static bool _isActive(DownloadEntry entry) =>
      entry.status == DownloadStatus.queued ||
      entry.status == DownloadStatus.downloading;

  List<DownloadEntry> get active => entries.value.where(_isActive).toList();

  /// Downloads [song] with [save]. Asking again for a song that is queued or
  /// downloading shares that download. Returns whether the song was saved.
  ///
  /// [cancelled] is asked when its turn comes, to leave the queue; a shared
  /// download leaves it only when everyone who asked for it says so.
  Future<bool> download(
    Map song,
    SongSaver save, {
    bool Function()? cancelled,
  }) {
    final ytid = song['ytid'].toString();
    _watchOffline();
    if (offlineMode.value) return Future.value(false);
    final asker = cancelled ?? _never;
    if (_inFlight[ytid] case final request?) {
      request.askers.add(asker);
      return request.result;
    }
    final request = _Request()..askers.add(asker);
    // A block body: `remove` returns this very request, whose future
    // whenComplete would then wait for for ever.
    request.result = _run(song, save, request).whenComplete(() {
      _inFlight.remove(ytid);
    });
    return (_inFlight[ytid] = request).result;
  }

  static bool _never() => false;

  Future<bool> _run(Map song, SongSaver save, _Request request) async {
    final earlier = entries.value
        .where((e) => e.ytid == song['ytid'].toString() && !_isActive(e))
        .firstOrNull;
    final epoch = _historyEpoch;
    final stopEpoch = _stopEpoch;
    final entry = queued(song);
    await _acquire();
    try {
      if (stopEpoch != _stopEpoch ||
          request.askers.every((cancelled) => cancelled())) {
        // The history it came from may have been cleared meanwhile.
        entries.value = [
          if (epoch == _historyEpoch) ?earlier,
          ...entries.value.where((e) => e != entry),
        ];
        _checkIdle();
        return false;
      }
      _track(entry..status = DownloadStatus.downloading);
      await save(entry.song, (value) {
        if (stopEpoch != _stopEpoch) throw const DownloadStopped();
        entry.progress.value = value;
      });
      finished(entry);
      return true;
    } on DownloadStopped {
      entries.value = entries.value.where((e) => e != entry).toList();
      _checkIdle();
      return false;
    } catch (error) {
      failed(entry, error);
      return false;
    } finally {
      _release();
    }
  }

  /// Stops what is queued and what is downloading (offline mode, deleting
  /// every download), and waits for it to let go of its files. What stopped
  /// leaves no entry: it was not tried to the end.
  Future<void> stopAll() async {
    _stopEpoch++;
    for (var i = 0; i < 100 && entries.value.any(_isActive); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> _acquire() async {
    if (_running < maxConcurrent) {
      _running++;
      return;
    }
    final turn = Completer<void>();
    _waiting.add(turn);
    await turn.future;
  }

  // A waiting download takes over the slot, so the count stays as it is.
  void _release() =>
      _waiting.isEmpty ? _running-- : _waiting.removeFirst().complete();

  DownloadEntry queued(Map song) => _add(song, DownloadStatus.queued);

  DownloadEntry started(Map song) => _add(song, DownloadStatus.downloading);

  DownloadEntry _add(Map song, DownloadStatus status) {
    final entry = DownloadEntry(
      song: Map<String, dynamic>.from(song),
      status: status,
      time: DateTime.now(),
    );
    entries.value = [
      entry,
      ...entries.value.where((other) => other.ytid != entry.ytid),
    ];
    _idleTimer?.cancel();
    idle.value = false;
    return entry;
  }

  /// Keeps a run of downloads open, for whoever starts one: from the tap,
  /// through loading what is to be downloaded, to the last song. Nothing is
  /// told, and no notice appears, until every open run is closed and nothing
  /// is queued or downloading. Downloads that no run holds (a single song)
  /// are grouped by the margin alone.
  DownloadRun openRun() {
    final run = DownloadRun._(this);
    _runs.add(run);
    _idleTimer?.cancel();
    idle.value = false;
    return run;
  }

  /// Runs [body] as one run: opened before it, closed after it, however it
  /// ends.
  Future<T> inRun<T>(Future<T> Function() body) async {
    final run = openRun();
    try {
      return await body();
    } finally {
      run.close();
    }
  }

  void _closeRun(DownloadRun run) {
    if (_runs.remove(run)) _checkIdle();
  }

  /// Starts the wait that ends in [idle] and the [batch] notice, if nothing
  /// is left to do.
  void _checkIdle() {
    if (_runs.isNotEmpty || entries.value.any(_isActive)) return;
    _idleTimer?.cancel();
    _idleTimer = Timer(idleMargin, () {
      if (_runs.isNotEmpty || entries.value.any(_isActive)) return;
      idle.value = true;
      if (_batchFailed.isNotEmpty) {
        batch.value = (
          failed: _batchFailed.length,
          unavailable: _batchFailed.values.where((gone) => gone).length,
          id: ++_batches,
        );
      }
      _batchFailed.clear();
    });
  }

  /// Tells the listeners that [entry] changed in place.
  void _track(DownloadEntry entry) => entries.value = [...entries.value];

  void finished(DownloadEntry entry) {
    _batchFailed.remove(entry.ytid);
    unavailableSongs.markAvailable(entry.ytid);
    _settle(entry, DownloadStatus.done);
  }

  /// Settles [entry] as failed. A song YouTube reports as unplayable is also
  /// remembered as unavailable, which only a download attempt does.
  void failed(DownloadEntry entry, Object? error) {
    entry.failure = failureFor(error);
    final gone = entry.failure == DownloadFailure.unavailable;
    _batchFailed[entry.ytid] = gone;
    if (gone) unavailableSongs.markUnavailable(entry.ytid);
    _settle(entry, DownloadStatus.failed);
  }

  /// Drops the finished entries of [ytids]: songs that were replaced.
  void forget(Iterable<String> ytids) {
    final gone = ytids.toSet();
    _historyEpoch++;
    _batchFailed.removeWhere((ytid, _) => gone.contains(ytid));
    entries.value = [
      for (final entry in entries.value)
        if (_isActive(entry) || !gone.contains(entry.ytid)) entry,
    ];
    _schedulePersist();
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
        if (_isActive(other) || kept++ < _maxHistory) other,
    ];
    _schedulePersist();
    _checkIdle();
  }

  /// Forgets everything, including what is running: a clean slate for tests.
  @visibleForTesting
  void reset() {
    _idleTimer?.cancel();
    _runs.clear();
    entries.value = [];
    idle.value = true;
    batch.value = null;
    _batchFailed.clear();
  }

  void clearHistory() {
    _historyEpoch++;
    entries.value = active;
    _schedulePersist();
  }

  /// Batches the writes of a playlist download into one per [_persistDelay].
  void _schedulePersist() {
    if (persist) _persistTimer ??= Timer(_persistDelay, flush);
  }

  /// Writes the history now.
  void flush() {
    _persistTimer?.cancel();
    _persistTimer = null;
    final history = [
      for (final entry in entries.value)
        if (!_isActive(entry)) entry.toMap(),
    ];
    Hive.box('userNoBackup').put(_storageKey, history);
  }

  @visibleForTesting
  static DownloadFailure failureFor(Object? error) {
    if (error == null ||
        (error is VideoUnplayableException && !isDeviceBlock(error))) {
      return DownloadFailure.unavailable;
    }
    if (error is SocketException ||
        error is HttpException ||
        error is TimeoutException ||
        error is http.ClientException ||
        error is YoutubeExplodeException) {
      return DownloadFailure.network;
    }
    return DownloadFailure.other;
  }
}

/// An open run of downloads, see [DownloadManager.openRun].
final class DownloadRun {
  DownloadRun._(this._manager);

  final DownloadManager _manager;

  /// Ends the run; closing it again does nothing.
  void close() => _manager._closeRun(this);
}

/// How many songs failed in a run of downloads, and how many of those are
/// unavailable on YouTube. `id` tells one run from the next.
typedef DownloadBatch = ({int failed, int unavailable, int id});

/// A download that may be asked for by several callers, each with its own
/// way to say it no longer wants it.
class _Request {
  late final Future<bool> result;
  final askers = <bool Function()>[];
}
