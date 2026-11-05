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

import 'dart:convert';
import 'dart:math';

import 'package:musify/main.dart';
import 'package:musify/services/proxy_manager.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/formatter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class PlaylistSharingService {
  static const _expandBatch = 8;
  static const maxSongs = 1000;
  static const maxTitleLength = 100;
  static const maxImageLength = 2048;

  static final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
  // Control characters plus bidi and zero-width overrides.
  static final _unsafeTitleChars = RegExp(
    r'[\u0000-\u001F\u007F-\u009F\u200B-\u200F'
    r'\u202A-\u202E\u2066-\u2069\uFEFF]',
  );

  /// Decodes a shared link and keeps only what Zenify writes itself:
  /// title, optional http(s) image, a fixed source and 1..[maxSongs] video
  /// ids. Returns null for anything else; makes no network request.
  static Map<String, dynamic>? parseCompactPlaylist(String encodedPlaylist) {
    try {
      final decoded = json.decode(
        utf8.decode(base64Url.decode(encodedPlaylist)),
      );
      if (decoded is! Map) return null;

      final rawTitle = decoded['title'];
      if (rawTitle is! String) return null;
      final cleanTitle = rawTitle.replaceAll(_unsafeTitleChars, '').trim();
      final title = String.fromCharCodes(cleanTitle.runes.take(maxTitleLength))
          .trim();
      if (title.isEmpty) return null;

      final rawList = decoded['list'];
      if (rawList is! List || rawList.isEmpty || rawList.length > maxSongs) {
        return null;
      }
      final list = <String>[];
      for (final id in rawList) {
        if (id is! String || !_videoId.hasMatch(id)) return null;
        list.add(id);
      }

      final image = decoded['image'];
      return {
        'title': title,
        if (image is String && _isWebImage(image)) 'image': image,
        'source': 'user-created',
        'list': list,
      };
    } catch (_) {
      return null;
    }
  }

  static bool _isWebImage(String image) {
    if (image.length > maxImageLength) return false;
    final uri = Uri.tryParse(image);
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// Fetches the songs of a map from [parseCompactPlaylist].
  static Future<Map<String, dynamic>> expandCompactPlaylist(
    Map<String, dynamic> compactPlaylist,
  ) async {
    final List<dynamic> songIds = compactPlaylist['list'];
    YoutubeExplode? ytClient;
    try {
      if (useProxy.value) {
        ytClient = await ProxyManager().getYoutubeExplodeClient();
      } else {
        ytClient = ProxyManager().getClientSync();
      }

      // A few at a time: a long playlist must not become hundreds of
      // requests at once.
      final expandedSongs = List<Map<String, dynamic>?>.filled(
        songIds.length,
        null,
      );
      for (var start = 0; start < songIds.length; start += _expandBatch) {
        final end = min(start + _expandBatch, songIds.length);
        await Future.wait([
          for (var index = start; index < end; index++)
            () async {
              try {
                final video = await ytClient!.videos.get(songIds[index]);
                expandedSongs[index] = returnSongLayout(index, video);
              } catch (e, stackTrace) {
                logger.log(
                  'Error expanding song: ${songIds[index]}',
                  error: e,
                  stackTrace: stackTrace,
                );
              }
            }(),
        ]);
      }

      return {
        ...compactPlaylist,
        'list': expandedSongs.where((song) => song != null).toList(),
      };
    } finally {
      try {
        if (useProxy.value) {
          ytClient?.close();
        }
      } catch (_) {}
    }
  }
}
