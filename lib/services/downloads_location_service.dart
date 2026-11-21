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

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:musify/main.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/download_manager.dart';
import 'package:musify/services/io_service.dart';
import 'package:musify/services/playlist_download_service.dart';
import 'package:musify/utilities/platform_utils.dart';

/// Outcome of moving the downloads to another folder.
enum DownloadsMoveStatus {
  /// Everything was moved and the new folder is in use.
  moved,

  /// The new folder is in use, but some files could not be moved and still
  /// play from where they were.
  partiallyMoved,

  /// The folder could not be created or written to. Nothing changed.
  notWritable,

  /// A download or another storage operation is still using the folder.
  busy,
}

/// The desktop downloads folder. Changing it moves the files and rewrites the
/// stored paths. Kept in `userNoBackup`: it is a path on this machine only.
class DownloadsLocation {
  DownloadsLocation._();

  static const _storageKey = 'downloadsDirectory';

  /// The chosen folder was missing at startup (an unplugged drive); downloads
  /// use the default folder meanwhile, and the setting is kept.
  static bool unavailable = false;

  static String? get customPath {
    final value = Hive.box('userNoBackup').get(_storageKey);
    return value is String && value.isNotEmpty ? value : null;
  }

  static String get defaultPath => applicationDirPath;

  /// Resolves [downloadsDirPath]. Must run after [applicationDirPath] is set.
  static Future<void> initialise() async {
    downloadsDirPath = defaultPath;
    if (!isDesktopPlatform) return;

    final custom = customPath;
    if (custom == null) return;

    // Never recreated: it could fill the mount point of an unplugged drive.
    if (await Directory(custom).exists()) {
      downloadsDirPath = custom;
      unavailable = false;
    } else {
      unavailable = true;
      logger.log('Downloads folder $custom is unavailable, using the default');
    }
  }

  /// Moves the downloads to [newRoot], or back to the default when null.
  static Future<DownloadsMoveStatus> change(String? newRoot) async {
    if (!isDesktopPlatform)
      throw UnsupportedError('Custom download folders are desktop only');
    final manager = DownloadManager.instance;
    if (manager.storageBusy ||
        manager.hasPendingTransfers ||
        offlinePlaylistService.activeDownloads.isNotEmpty) {
      return DownloadsMoveStatus.busy;
    }
    return manager.withExclusiveStorage(() => _change(newRoot));
  }

  static Future<DownloadsMoveStatus> _change(String? newRoot) async {
    final target = _trimSeparator(newRoot ?? defaultPath);

    if (!await _prepare(target)) return DownloadsMoveStatus.notWritable;

    var failed = 0;
    final movedPaths = <String, String>{};
    final originals = <String, String>{};
    final sources = <String>{downloadsDirPath, defaultPath, ?customPath}
      ..remove(target);
    final referencedPaths = <String>{
      for (final song in userOfflineSongs.value.whereType<Map>())
        for (final key in ['audioPath', 'artworkPath'])
          if (song[key] case final String path when path.isNotEmpty)
            _pathKey(path),
    };

    try {
      for (final source in sources) {
        failed += await _moveFolderContents(
          source,
          target,
          referencedPaths,
          movedPaths,
          originals,
        );
      }

      // Copied, not moved: files outside our folders, such as an older
      // documents directory, may still belong to another Musify install.
      for (final song in userOfflineSongs.value) {
        if (song is! Map) continue;
        failed += await _copyReferencedFile(
          song['audioPath'],
          target,
          false,
          movedPaths,
        );
        failed += await _copyReferencedFile(
          song['artworkPath'],
          target,
          true,
          movedPaths,
        );
      }
    } catch (e, stackTrace) {
      failed++;
      logger.log('Moving downloads stopped', error: e, stackTrace: stackTrace);
    }

    // Keep the originals until the paths have been flushed. An interrupted
    // copy or a failed Hive write leaves the previous paths readable.
    await _commitPaths(target, movedPaths);
    for (final entry in originals.entries) {
      try {
        if (await FilePaths.canDeleteDownload(entry.key) &&
            !await FileSystemEntity.identical(entry.key, entry.value) &&
            await _sameContents(File(entry.key), File(entry.value))) {
          await File(entry.key).delete();
        }
      } on FileSystemException catch (error) {
        failed++;
        logger.log('Could not remove old download ${entry.key}: $error');
      }
    }

    downloadsDirPath = target;
    unavailable = false;
    await offlinePlaylistService.validateStoredPlaylists();

    for (final source in sources) {
      if (source != defaultPath) await _removeIfEmpty(source);
    }

    return failed == 0
        ? DownloadsMoveStatus.moved
        : DownloadsMoveStatus.partiallyMoved;
  }

  static Future<bool> _prepare(String root) async {
    try {
      for (final subDir in [FilePaths.tracksDir, FilePaths.artworksDir]) {
        final path = '$root/$subDir';
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.notFound) {
          await Directory(path).create(recursive: true);
        } else if (type != FileSystemEntityType.directory) {
          return false;
        }
      }

      final probe = await Directory('$root/${FilePaths.tracksDir}')
          .createTemp('.zenify-write-');
      await probe.delete();
      return true;
    } catch (e, stackTrace) {
      logger.log(
        'Downloads folder $root is not writable',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Returns how many files could not be moved.
  static Future<int> _moveFolderContents(
    String source,
    String target,
    Set<String> referencedPaths,
    Map<String, String> movedPaths,
    Map<String, String> originals,
  ) async {
    var failed = 0;
    for (final artwork in [false, true]) {
      final subDir = artwork ? FilePaths.artworksDir : FilePaths.tracksDir;
      final directory = Directory('$source/$subDir');
      if (await FileSystemEntity.type(directory.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        continue;
      }

      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File) continue;
        if (!FilePaths.isDownloadedFile(entity.path, artwork: artwork)) {
          continue;
        }
        final path = _pathKey(entity.path);
        if (source != defaultPath && !referencedPaths.contains(path)) continue;
        final name = entity.uri.pathSegments.last;
        final destination = '$target/$subDir/$name';
        if (await _copyToDestination(entity, destination)) {
          movedPaths[path] = destination;
          originals[entity.path] = destination;
        } else {
          failed++;
        }
      }
    }
    return failed;
  }

  static Future<int> _copyReferencedFile(
    Object? path,
    String target,
    bool artwork,
    Map<String, String> movedPaths,
  ) async {
    if (path is! String || path.isEmpty) return 0;
    if (movedPaths.containsKey(_pathKey(path))) return 0;
    final file = File(path);
    if (!await file.exists()) return 0;

    final subDir = artwork ? FilePaths.artworksDir : FilePaths.tracksDir;
    final destination = '$target/$subDir/${file.uri.pathSegments.last}';
    if (_pathKey(destination) == _pathKey(path)) return 0;
    if (!await _copyToDestination(file, destination)) return 1;
    movedPaths[_pathKey(path)] = destination;
    return 0;
  }

  static Future<bool> _copyToDestination(File source, String path) async {
    final destination = File(path);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.file) {
      // A previous interrupted migration may already have copied this file.
      return _sameContents(source, destination);
    }
    if (type != FileSystemEntityType.notFound) return false;

    try {
      final staging = await destination.parent.createTemp('.zenify-move-');
      try {
        final partial = await source.copy('${staging.path}/download.part');
        await destination.create(exclusive: true);
        try {
          await partial.rename(path);
        } catch (_) {
          await destination.delete();
          rethrow;
        }
      } finally {
        await staging.delete(recursive: true);
      }
      return true;
    } on FileSystemException catch (error) {
      logger.log('Could not copy ${source.path} to $path: $error');
      return false;
    }
  }

  static Future<bool> _sameContents(File a, File b) async {
    if (await a.length() != await b.length()) return false;
    if (await FileSystemEntity.identical(a.path, b.path)) return true;
    final hashes = await Future.wait([
      sha256.bind(a.openRead()).first,
      sha256.bind(b.openRead()).first,
    ]);
    return hashes.first == hashes.last;
  }

  /// Songs whose file did not move keep the path that still works.
  static String _pathKey(String path) {
    final value = File(path).absolute.uri.normalizePath().toFilePath();
    return Platform.isWindows ? value.toLowerCase() : value;
  }

  static Future<void> _commitPaths(
    String target,
    Map<String, String> movedPaths,
  ) async {
    Map rewrite(Map song) {
      final updated = Map<String, dynamic>.from(song);
      for (final key in ['audioPath', 'artworkPath']) {
        final path = updated[key];
        if (path is! String || path.isEmpty) continue;
        final moved = movedPaths[_pathKey(path)];
        if (moved != null) updated[key] = moved;
      }
      return updated;
    }

    final songs = [
      for (final song in userOfflineSongs.value)
        if (song is Map) rewrite(song) else song,
    ];
    final playlists = offlinePlaylistService.offlinePlaylists;
    final updatedPlaylists = [
      for (final playlist in playlists.value)
        if (playlist is Map && playlist['list'] is List)
          {
            ...Map<String, dynamic>.from(playlist),
            'list': [
              for (final song in playlist['list'] as List)
                if (song is Map) rewrite(song) else song,
            ],
          }
        else
          playlist,
    ];
    final box = Hive.box('userNoBackup');
    final useDefault = target == _trimSeparator(defaultPath);
    await box.putAll({
      'offlineSongs': songs,
      'offlinePlaylists': updatedPlaylists,
      if (!useDefault) _storageKey: target,
    });
    if (useDefault) await box.delete(_storageKey);
    await box.flush();
    userOfflineSongs.value = songs;
    playlists.value = updatedPlaylists;
  }

  static Future<void> _removeIfEmpty(String root) async {
    for (final subDir in [FilePaths.tracksDir, FilePaths.artworksDir]) {
      try {
        final directory = Directory('$root/$subDir');
        if (await FileSystemEntity.type(directory.path, followLinks: false) ==
                FileSystemEntityType.directory &&
            await directory.list(followLinks: false).isEmpty) {
          await directory.delete();
        }
      } catch (_) {
        // Left in place: an empty folder is harmless.
      }
    }
  }

  static String _trimSeparator(String path) {
    var result = path;
    while (result.length > 1 &&
        (result.endsWith('/') || result.endsWith(r'\'))) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
