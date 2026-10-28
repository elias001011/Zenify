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

  /// Whether [path] is inside our download folders. Files elsewhere, such as
  /// a library copied from another Musify install, are never deleted.
  static bool isOwnDownload(String path) {
    String normalize(String value) {
      final result = value.replaceAll(r'\', '/');
      return Platform.isWindows ? result.toLowerCase() : result;
    }

    final file = normalize(path);
    return {downloadsDirPath, applicationDirPath}.any((root) {
      final prefix = normalize(root);
      return file.startsWith(prefix.endsWith('/') ? prefix : '$prefix/');
    });
  }

  /// Deletes the files [offlineSongs] point at, plus any of ours left behind.
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
        '$downloadsDirPath/${artwork ? artworksDir : tracksDir}',
      );
      if (!await directory.exists()) continue;
      await for (final entity in directory.list()) {
        if (entity is File && isDownloadedFile(entity.path, artwork: artwork)) {
          paths.add(entity.path);
        }
      }
    }

    for (final path in paths) {
      final file = File(path);
      if (await file.exists()) await file.delete();
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
