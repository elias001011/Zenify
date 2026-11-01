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

Future<void> _queue = Future.value();

/// Runs [action] after every earlier change to the list. Adding, removing and
/// the startup migration all read and then write the list, so they run one
/// at a time: none can overwrite what another just saved.
Future<T> _serialized<T>(Future<T> Function() action) {
  final result = _queue.then((_) => action());
  _queue = result.then<void>((_) {}, onError: (_) {});
  return result;
}

Directory _storageDirectory() =>
    Directory('$applicationDirPath/$localFilesDirName');

/// Whether [path] is one of our copies, which are ours to delete.
bool _isKeptCopy(String path) =>
    path.startsWith('$applicationDirPath/$localFilesDirName/');

/// What makes two entries the same song: the content digest they were stored
/// with. Entries from earlier builds have none, so their id stands in.
String _digestKey(Map file) => (file['digest'] ?? file['ytid']).toString();

/// The SHA-1 of the file's content, or null when it cannot be read.
Future<Digest?> _digestOrNull(String source) async {
  try {
    return await sha1.bind(File(source).openRead()).first;
  } catch (_) {
    return null;
  }
}

/// Copies [source] into the app's own storage under its content's [digest],
/// and returns the copy's path. An existing copy is reused. The copy is checked
/// against the digest, so a source that changed meanwhile is never kept. The
/// original is never changed.
Future<String> _copyTo(String source, Digest digest) async {
  final extension = source.split('.').last.toLowerCase();
  final directory = _storageDirectory();
  await directory.create(recursive: true);
  final target = File('${directory.path}/$digest.$extension');
  if (await target.exists()) return target.path;

  // A name of its own, so two copies of the same song never share a file.
  final partial = File(
    '${target.path}.${DateTime.now().microsecondsSinceEpoch}.part',
  );
  try {
    await File(source).copy(partial.path);
    final copied = await sha1.bind(partial.openRead()).first;
    if (copied.toString() != digest.toString()) {
      throw StateError('The file changed while it was copied');
    }
    await partial.rename(target.path);
  } catch (_) {
    await _deleteQuietly(partial);
    rethrow;
  }
  return target.path;
}

/// Adds the audio files at [paths] that are not in the list yet. A file is
/// recognised by its content, so the same song picked twice, even under
/// another extension, is added once and copied once; a song already in the
/// list is not a failure. Files that are not audio, or cannot be read or
/// copied, are counted as failed.
Future<({int added, int failed})> addLocalFiles(Iterable<String> paths) =>
    _serialized(() async {
      final known = {for (final file in localFiles.value) _digestKey(file)};
      final added = <Map>[];
      var failed = 0;
      for (final path in paths) {
        final extension = path.split('.').last.toLowerCase();
        if (!_audioExtensions.contains(extension)) {
          failed++;
          continue;
        }
        final digest = await _digestOrNull(path);
        if (digest == null) {
          failed++;
          continue;
        }
        final key = digest.toString();
        if (known.contains(key)) continue;
        final String copy;
        try {
          copy = await _copyTo(path, digest);
        } catch (_) {
          failed++;
          continue;
        }
        known.add(key);
        final name = path.split(RegExp(r'[\\/]')).last;
        final dot = name.lastIndexOf('.');
        added.add({
          'ytid': '$localSongPrefix$key',
          'digest': key,
          'title': dot > 0 ? name.substring(0, dot) : name,
          'artist': '',
          'audioPath': copy,
        });
      }
      if (added.isNotEmpty) {
        final updated = [...localFiles.value, ...added];
        try {
          await Hive.box('userNoBackup').put(_storageKey, updated);
          localFiles.value = updated;
        } catch (_) {
          // Not listed, so not added: their copies are swept at the next start.
          return (added: 0, failed: failed + added.length);
        }
      }
      return (added: added.length, failed: failed);
    });

/// Where the copy of the local file [id] is now, or null if it is not listed.
/// Playback asks here rather than trusting the path a queue kept, which may
/// still point into the picker's cache.
String? localFileCopyPath(String id) {
  for (final file in localFiles.value) {
    final aliases = file['aliases'];
    if (file['ytid'] == id || (aliases is List && aliases.contains(id))) {
      return file['audioPath']?.toString();
    }
  }
  return null;
}

/// Moves entries saved by earlier builds, which pointed at the picker's cache,
/// into the app's own storage. An entry that is a copy of a song already in
/// the list is dropped, so a file saved twice is kept once; the entry kept
/// remembers the dropped id, so a queue saved with it still plays. An entry
/// whose file is gone stays in the list as it is, so the user can see it and
/// remove it.
Future<void> keepLocalFileCopies() => _serialized(() async {
  final snapshot = List<Map>.of(localFiles.value);
  final needsCopy = <bool>[];
  for (final file in snapshot) {
    final path = file['audioPath']?.toString() ?? '';
    needsCopy.add(
      path.isNotEmpty && !_isKeptCopy(path) && await File(path).exists(),
    );
  }
  if (!needsCopy.contains(true)) return;

  // Entries that stay as they are claim their songs first.
  final taken = {
    for (var i = 0; i < snapshot.length; i++)
      if (!needsCopy[i]) _digestKey(snapshot[i]),
  };
  // Each moved entry keeps its id, so a removal that is already on its way
  // still finds it. It becomes its copy, or is dropped as a duplicate; a
  // failed copy leaves the entry as it was.
  final outcome = <Map?>[];
  final dropped = <String, List<String>>{};
  for (var i = 0; i < snapshot.length; i++) {
    final file = snapshot[i];
    if (!needsCopy[i]) {
      outcome.add(file);
      continue;
    }
    final digest = await _digestOrNull(file['audioPath'].toString());
    if (digest == null) {
      outcome.add(file);
      continue;
    }
    final key = digest.toString();
    if (taken.contains(key)) {
      dropped.putIfAbsent(key, () => []).add(file['ytid'].toString());
      outcome.add(null);
      continue;
    }
    try {
      final copy = await _copyTo(file['audioPath'].toString(), digest);
      taken.add(key);
      outcome.add({...file, 'digest': key, 'audioPath': copy});
    } catch (_) {
      outcome.add(file);
    }
  }

  // Only this queue writes the list, so it still matches the snapshot here.
  final updated = [
    for (final replacement in outcome)
      if (replacement != null)
        if (dropped[_digestKey(replacement)] case final ids?)
          {
            ...replacement,
            'aliases': [...?(replacement['aliases'] as List?), ...ids],
          }
        else
          replacement,
  ];
  localFiles.value = updated;
  await Hive.box('userNoBackup').put(_storageKey, updated);
});

/// Deletes the copies in the app's storage that no entry points to: what a
/// removal could not delete (Windows keeps a playing file open) and what an
/// interrupted copy left behind. A list that could not be read deletes
/// nothing.
Future<void> removeUnlistedLocalCopies() => _serialized(() async {
  if (Hive.box('userNoBackup').get(_storageKey) is! List) return;
  final directory = _storageDirectory();
  if (!await directory.exists()) return;
  final listed = {
    for (final file in localFiles.value)
      if (file['audioPath']?.toString() case final path?) _baseName(path),
  };
  await for (final entity in directory.list()) {
    if (entity is File && !listed.contains(_baseName(entity.path))) {
      await _deleteQuietly(entity);
    }
  }
});

String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;

/// Takes a file out of the list. Its copy in the app's storage is deleted;
/// the file the user picked is left alone.
Future<void> removeLocalFile(String id) => _serialized(() async {
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
});

Future<void> _deleteQuietly(File file) async {
  try {
    if (await file.exists()) await file.delete();
  } catch (_) {
    // A copy that cannot be deleted is harmless: it is not listed any more.
  }
}
