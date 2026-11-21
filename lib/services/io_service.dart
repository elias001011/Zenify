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

late String applicationDirPath;

/// Root of `tracks/` and `artworks/`: [applicationDirPath] unless a desktop
/// user chose another folder (see `downloads_location_service.dart`).
late String downloadsDirPath;

/// Where local files are copied to, under [applicationDirPath]. Not a download.
const localFilesDirName = 'local_files';

class FilePaths {
  // File extensions
  static const String audioExtension = '.m4a';
  static const String artworkExtension = '.jpg';

  // Directory names
  static const String tracksDir = 'tracks';
  static const String artworksDir = 'artworks';

  // Get full paths for various file types
  static String getAudioPath(String songId) {
    return '$downloadsDirPath/$tracksDir/$songId$audioExtension';
  }

  static String getArtworkPath(String songId) {
    return '$downloadsDirPath/$artworksDir/$songId$artworkExtension';
  }

  /// A YouTube id plus our extension, so the user's own files are never touched.
  static bool isDownloadedFile(String path, {required bool artwork}) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final extension = artwork ? artworkExtension : audioExtension;
    if (!name.endsWith(extension)) return false;
    return _youtubeIdPattern.hasMatch(
      name.substring(0, name.length - extension.length),
    );
  }

  static final _youtubeIdPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static String _normalizedPath(String path) {
    final normalized = File(path).absolute.uri.normalizePath().toFilePath();
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  static bool _inside(String path, String root) {
    final prefix = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    return path.startsWith(prefix);
  }

  /// Whether [path] is lexically inside our storage, excluding local files.
  static bool isOwnDownload(String path) {
    final file = _normalizedPath(path);
    if (_inside(
      file,
      _normalizedPath('$applicationDirPath/$localFilesDirName'),
    )) {
      return false;
    }
    return {
      downloadsDirPath,
      applicationDirPath,
    }.any((root) => _inside(file, _normalizedPath(root)));
  }

  /// Checks the real file too: a link inside our folder may lead outside it.
  static Future<bool> canDeleteDownload(String path) async {
    if (!isOwnDownload(path)) return false;
    try {
      final file = _normalizedPath(await File(path).resolveSymbolicLinks());
      final local = Directory('$applicationDirPath/$localFilesDirName');
      if (await local.exists() &&
          _inside(file, _normalizedPath(await local.resolveSymbolicLinks()))) {
        return false;
      }
      for (final root in {downloadsDirPath, applicationDirPath}) {
        final directory = Directory(root);
        if (await directory.exists() &&
            _inside(
              file,
              _normalizedPath(await directory.resolveSymbolicLinks()),
            )) {
          return true;
        }
      }
    } on FileSystemException {
      // Missing or unreadable: ownership cannot be established.
    }
    return false;
  }

  /// Deletes registered downloads and orphaned files in the app's own folder.
  static Future<void> deleteDownloadedFiles(List offlineSongs) async {
    final paths = <String>{
      for (final song in offlineSongs)
        if (song is Map) ...[
          if (song['audioPath'] case final String path when isOwnDownload(path))
            path,
          if (song['artworkPath'] case final String path
              when isOwnDownload(path))
            path,
        ],
    };

    for (final artwork in [false, true]) {
      final directory = Directory(
        '$applicationDirPath/${artwork ? artworksDir : tracksDir}',
      );
      if (await FileSystemEntity.type(directory.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        continue;
      }
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is File && isDownloadedFile(entity.path, artwork: artwork)) {
          paths.add(entity.path);
        }
      }
    }

    for (final path in paths) {
      final file = File(path);
      if (await canDeleteDownload(path)) await file.delete();
    }
  }

  // Ensure directories exist
  static Future<void> ensureDirectoriesExist() async {
    final tracksDirectory = Directory('$downloadsDirPath/$tracksDir');
    final artworksDirectory = Directory('$downloadsDirPath/$artworksDir');

    if (!await tracksDirectory.exists()) {
      await tracksDirectory.create(recursive: true);
    }

    if (!await artworksDirectory.exists()) {
      await artworksDirectory.create(recursive: true);
    }
  }
}
