import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// Audio files kept on this device and played from it. They stay apart from
/// the library on purpose: no downloads, playlists, likes, recap, history,
/// backups or Local Sync reach them, and the player never looks them up
/// online. Their ids start with [localSongPrefix], which is how the rest of
/// the app tells them apart.
const localSongPrefix = 'local:';

const _storageKey = 'localFiles';

const _audioExtensions = {'mp3', 'm4a', 'aac', 'flac', 'ogg', 'opus', 'wav'};

bool isLocalSongId(Object? ytid) =>
    ytid is String && ytid.startsWith(localSongPrefix);

bool isLocalSong(Map? song) => song != null && isLocalSongId(song['ytid']);

/// The local files the user added, newest last. Kept in the device-only box,
/// which backups and Local Sync never read.
final localFiles = ValueNotifier<List<Map>>(_load());

List<Map> _load() {
  try {
    final raw = Hive.box('userNoBackup').get(_storageKey);
    if (raw is List)
      return [
        for (final item in raw)
          if (item is Map) item,
      ];
  } catch (_) {
    // A broken list is treated as empty, not fatal.
  }
  return [];
}

/// Adds the audio files at [paths] that are not in the list yet, and returns
/// how many were added. Other files are skipped. The files themselves are
/// never changed or copied.
Future<int> addLocalFiles(Iterable<String> paths) async {
  final known = {for (final file in localFiles.value) file['ytid']};
  final added = <Map>[];
  for (final path in paths) {
    final extension = path.split('.').last.toLowerCase();
    if (!_audioExtensions.contains(extension)) continue;
    final id = '$localSongPrefix${sha1.convert(utf8.encode(path))}';
    if (!known.add(id)) continue;
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    added.add({
      'ytid': id,
      'title': dot > 0 ? name.substring(0, dot) : name,
      'artist': '',
      'audioPath': path,
    });
  }
  if (added.isEmpty) return 0;
  final updated = [...localFiles.value, ...added];
  localFiles.value = updated;
  await Hive.box('userNoBackup').put(_storageKey, updated);
  return added.length;
}

/// Takes a file out of the list. The file on the device is left alone.
Future<void> removeLocalFile(String id) async {
  final updated = [
    for (final file in localFiles.value)
      if (file['ytid'] != id) file,
  ];
  if (updated.length == localFiles.value.length) return;
  localFiles.value = updated;
  await Hive.box('userNoBackup').put(_storageKey, updated);
}
