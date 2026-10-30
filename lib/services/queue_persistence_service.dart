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
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:hive/hive.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/utilities/media_duration.dart';

typedef SavedQueue = ({
  List<Map> songs,
  List<Map> original,
  int index,
  Duration position,
  bool keepGoing,
});

/// Device-local playback state. Queue edits are coalesced; position is a
/// separate small record, so playback never rewrites the whole song list.
class QueuePersistenceService {
  static const queueKey = 'playbackQueue';
  static const positionKey = 'playbackQueuePosition';
  static const limit = 500;
  Timer? _timer;
  ({List<Map> songs, List<Map>? original, int index, bool keepGoing})? _pending;

  /// The entries and order last saved; a track change within the same queue
  /// only moves the small position record.
  String? _savedShape;

  Map _song(Map song) => {
    for (final key in const [
      'ytid',
      'queueEntryId',
      'title',
      'artist',
      'artistId',
      'videoAuthor',
      'image',
      'lowResImage',
      'highResImage',
      'audioPath',
      'artworkPath',
      'artWorkPath',
      'isLive',
      'isManuallyAdded',
      'isAutoPicked',
    ])
      if (song[key] is String || song[key] is bool || song[key] is num)
        key: song[key],
    if (readMediaDuration(song['duration']) case final duration?)
      'duration': duration.inMilliseconds / 1000,
  };

  void saveQueue(
    List<Map> songs,
    List<Map> original,
    int index, {
    bool keepGoing = false,
  }) {
    final start = max(0, min(index - limit ~/ 2, songs.length - limit));
    final window = songs.skip(start).take(limit).toList();
    final ids = [for (final song in window) song['queueEntryId']];
    final idSet = ids.toSet();
    final originalIds = [
      for (final song in original)
        if (idSet.contains(song['queueEntryId'])) song['queueEntryId'],
    ];
    // Unshuffled, the original order is the queue itself: not saved twice.
    final shuffled = !listEquals(ids, originalIds);
    final shape =
        '$start|$keepGoing|${ids.join(',')}|${shuffled ? originalIds.join(',') : ''}';

    if (shape == _savedShape && _pending == null) {
      // Same queue, another song: remember which, cheaply.
      if (index >= 0 && index < songs.length) {
        final entry = songs[index]['queueEntryId'];
        if (entry is String) savePosition(entry, Duration.zero);
      }
      return;
    }
    _savedShape = shape;
    // The position record names the current song; keep it so.
    if (index >= 0 && index < songs.length && Hive.isBoxOpen('userNoBackup')) {
      final entry = songs[index]['queueEntryId'];
      final saved = Hive.box('userNoBackup').get(positionKey);
      if (entry is String && (saved is! Map || saved['entry'] != entry)) {
        savePosition(entry, Duration.zero);
      }
    }
    _pending = (
      keepGoing: keepGoing,
      songs: window,
      original: shuffled
          ? [
              for (final song in original)
                if (idSet.contains(song['queueEntryId'])) song,
            ]
          : null,
      index: window.isEmpty ? 0 : (index - start).clamp(0, window.length - 1),
    );
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), () => unawaited(flush()));
  }

  void savePosition(String entryId, Duration position) {
    if (!Hive.isBoxOpen('userNoBackup')) return;
    unawaited(
      Hive.box('userNoBackup')
          .put(positionKey, {
            'entry': entryId,
            'ms': max(0, position.inMilliseconds),
          })
          .catchError((Object error, StackTrace stack) {
            logger.log(
              'Could not remember playback position',
              error: error,
              stackTrace: stack,
            );
          }),
    );
  }

  SavedQueue? read() {
    if (!Hive.isBoxOpen('userNoBackup')) return null;
    final box = Hive.box('userNoBackup');
    final data = box.get(queueKey);
    if (data is! Map || data['version'] != 1 || data['songs'] is! List)
      return null;
    List<Map> songsOf(dynamic value) => value is List
        ? value
              .take(limit)
              .whereType<Map>()
              .where(
                (song) =>
                    song['ytid'] is String &&
                    (song['ytid'] as String).isNotEmpty &&
                    song['queueEntryId'] is String &&
                    (song['queueEntryId'] as String).isNotEmpty,
              )
              .map(_song)
              .toList()
        : [];
    final songs = songsOf(data['songs']);
    if (songs.isEmpty ||
        songs.length != (data['songs'] as List).length ||
        songs.map((song) => song['queueEntryId']).toSet().length !=
            songs.length)
      return null;
    var index = data['index'];
    if (index is! int || index < 0 || index >= songs.length) return null;
    // The position record names the song last played, which track changes
    // update without rewriting the queue.
    final saved = box.get(positionKey);
    if (saved is Map) {
      final at = songs.indexWhere(
        (song) => song['queueEntryId'] == saved['entry'],
      );
      if (at != -1) index = at;
    }
    final ids = songs.map((song) => song['queueEntryId']).toSet();
    final original = songsOf(data['original']);
    final validOriginal =
        original.length == songs.length &&
        original.map((song) => song['queueEntryId']).toSet().length ==
            ids.length &&
        original.every((song) => ids.contains(song['queueEntryId']));
    var position = Duration.zero;
    if (saved is Map &&
        saved['entry'] == songs[index]['queueEntryId'] &&
        saved['ms'] is int) {
      position = Duration(milliseconds: max(0, saved['ms'] as int));
      final duration = readMediaDuration(songs[index]['duration']);
      if (songs[index]['isLive'] == true ||
          (duration != null && position >= duration))
        position = Duration.zero;
    }
    return (
      songs: songs,
      original: validOriginal ? original : List<Map>.of(songs),
      index: index,
      position: position,
      keepGoing: data['keepGoing'] == true,
    );
  }

  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final pending = _pending;
    _pending = null;
    if (!Hive.isBoxOpen('userNoBackup')) return;
    try {
      final box = Hive.box('userNoBackup');
      if (pending != null) {
        // Copied now, after the burst of changes, not on every call.
        await box.put(queueKey, {
          'version': 1,
          'songs': pending.songs.map(_song).toList(),
          'original': pending.original?.map(_song).toList(),
          'index': pending.index,
          'keepGoing': pending.keepGoing,
        });
      }
      await box.flush();
    } catch (error, stack) {
      logger.log(
        'Could not remember playback queue',
        error: error,
        stackTrace: stack,
      );
    }
  }
}
