import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/io_service.dart';

/// Audio files kept on this device and played from it. They stay apart from
/// the library on purpose: no downloads, playlists, likes, recap, history,
/// backups or Local Sync reach them, and the player never looks them up
/// online. Their ids start with [localSongPrefix], which is how the rest of
/// the app tells them apart.
///
/// Each file is copied into the app's own storage when it is added. The
/// picker's paths point at its temporary cache, which Android may clear, so
/// the copy is what keeps the song playable.
const localSongPrefix = 'local:';

const localFilesDirName = 'local_files';

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

Directory _storageDirectory() =>
    Directory('$applicationDirPath/$localFilesDirName');

/// Whether [path] is one of our copies, which are ours to delete.
bool _isKeptCopy(String path) =>
    path.startsWith('$applicationDirPath/$localFilesDirName/');

/// Copies [source] into the app's own storage, named by its content, and
/// returns the new id and path. The same file added twice is one copy and one
/// entry. The original is never changed.
Future<({String id, String path})> _keepCopy(String source) async {
  final extension = source.split('.').last.toLowerCase();
  final digest = await sha1.bind(File(source).openRead()).first;
  final directory = _storageDirectory();
  await directory.create(recursive: true);
  final target = File('${directory.path}/$digest.$extension');
  if (!await target.exists()) {
    // Copy under a temporary name, so an interrupted copy is never kept.
    final partial = File('${target.path}.part');
    await File(source).copy(partial.path);
    await partial.rename(target.path);
  }
  return (id: '$localSongPrefix$digest', path: target.path);
}

/// [_keepCopy], or null when the file cannot be read.
Future<({String id, String path})?> _keepCopyOrNull(String source) async {
  try {
    return await _keepCopy(source);
  } catch (_) {
    return null;
  }
}

/// Adds the audio files at [paths] that are not in the list yet, and returns
/// how many were added. Other files, and files that cannot be read, are
/// skipped.
Future<int> addLocalFiles(Iterable<String> paths) async {
  final known = {for (final file in localFiles.value) file['ytid']};
  final added = <Map>[];
  for (final path in paths) {
    final extension = path.split('.').last.toLowerCase();
    if (!_audioExtensions.contains(extension)) continue;
    final kept = await _keepCopyOrNull(path);
    if (kept == null || !known.add(kept.id)) continue;
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    added.add({
      'ytid': kept.id,
      'title': dot > 0 ? name.substring(0, dot) : name,
      'artist': '',
      'audioPath': kept.path,
    });
  }
  if (added.isEmpty) return 0;
  final updated = [...localFiles.value, ...added];
  localFiles.value = updated;
  await Hive.box('userNoBackup').put(_storageKey, updated);
  return added.length;
}

/// Moves entries saved by earlier builds, which pointed at the picker's cache,
/// into the app's own storage. An entry whose file is gone stays in the list
/// as it is, so the user can see it and remove it.
Future<void> keepLocalFileCopies() async {
  final updated = <Map>[];
  var changed = false;
  for (final file in localFiles.value) {
    final path = file['audioPath']?.toString() ?? '';
    if (path.isEmpty || _isKeptCopy(path) || !await File(path).exists()) {
      updated.add(file);
      continue;
    }
    final kept = await _keepCopyOrNull(path);
    if (kept == null) {
      updated.add(file);
      continue;
    }
    changed = true;
    if (updated.any((other) => other['ytid'] == kept.id)) continue;
    updated.add({...file, 'ytid': kept.id, 'audioPath': kept.path});
  }
  if (!changed) return;
  localFiles.value = updated;
  await Hive.box('userNoBackup').put(_storageKey, updated);
}

/// Takes a file out of the list. Its copy in the app's storage is deleted;
/// the file the user picked is left alone.
Future<void> removeLocalFile(String id) async {
  final removed = [
    for (final file in localFiles.value)
      if (file['ytid'] == id) file,
  ];
  if (removed.isEmpty) return;
  final updated = [
    for (final file in localFiles.value)
      if (file['ytid'] != id) file,
  ];
  localFiles.value = updated;
  await Hive.box('userNoBackup').put(_storageKey, updated);
  for (final file in removed) {
    final path = file['audioPath']?.toString() ?? '';
    if (_isKeptCopy(path)) await _deleteQuietly(File(path));
  }
}

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {
    // A copy that cannot be deleted is harmless: it is not listed any more.
  }
}
