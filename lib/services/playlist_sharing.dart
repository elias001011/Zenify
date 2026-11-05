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

  static Future<Map<String, dynamic>?> decodeAndExpandPlaylist(
    String encodedPlaylist,
  ) async {
    try {
      final jsonString = utf8.decode(base64Url.decode(encodedPlaylist));
      final compactPlaylist = json.decode(jsonString) as Map<String, dynamic>;
      return await expandCompactPlaylist(compactPlaylist);
    } catch (e, stackTrace) {
      logger.log('Failed to decode playlist', error: e, stackTrace: stackTrace);
      return null;
    }
  }
}
