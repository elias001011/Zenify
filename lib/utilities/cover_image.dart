/*
 *     Copyright (C) 2025 Valeri Gokadze
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
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:musify/main.dart' show logger;
import 'package:musify/services/playlists_manager.dart';

/// The longest side of a playlist cover, in pixels: far more than it is ever
/// shown at.
const coverSide = 640;

/// A cover is kept as text inside its playlist, and goes wherever the library
/// goes (every write of the playlists, every sync). A photo from a camera is
/// several megabytes, so a larger one is shrunk.
const _coverLimit = 150 * 1024;

/// [bytes] as a JPEG no longer than [coverSide] on its longest side, or
/// [bytes] themselves when that is not smaller or they are not an image.
Uint8List shrinkCover(Uint8List bytes) {
  if (bytes.length <= _coverLimit) return bytes;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final landscape = decoded.width >= decoded.height;
  final longest = landscape ? decoded.width : decoded.height;
  final resized = longest <= coverSide
      ? decoded
      : img.copyResize(
          decoded,
          width: landscape ? coverSide : null,
          height: landscape ? null : coverSide,
          interpolation: img.Interpolation.average,
        );
  final smaller = img.encodeJpg(resized, quality: 82);
  return smaller.length < bytes.length ? smaller : bytes;
}

/// [shrinkCover], off the interface's thread: decoding a photo takes a while.
Future<Uint8List> shrinkCoverInBackground(Uint8List bytes) =>
    bytes.length <= _coverLimit
    ? Future.value(bytes)
    : Isolate.run(() => shrinkCover(bytes));

/// A cover stored as a data URI, shrunk if it is large; the same string
/// otherwise.
Future<String> shrinkCoverDataUri(String dataUri) async {
  final comma = dataUri.indexOf(',');
  if (!dataUri.startsWith('data:image') || comma == -1) return dataUri;
  final bytes = base64Decode(dataUri.substring(comma + 1));
  final smaller = await shrinkCoverInBackground(bytes);
  if (identical(smaller, bytes)) return dataUri;
  return 'data:image/jpeg;base64,${base64Encode(smaller)}';
}

/// Shrinks the large covers of the playlists you made, which older versions
/// kept as picked. Each is written back through the playlists, so the other
/// devices receive the smaller one.
Future<void> shrinkStoredCovers() async {
  try {
    for (final playlist in getUserCustomPlaylists()) {
      final cover = playlist['image'];
      if (cover is! String || cover.length < _coverLimit * 4 ~/ 3) continue;
      final smaller = await shrinkCoverDataUri(cover);
      if (smaller == cover) continue;
      await replaceCustomPlaylist(playlist['ytid'].toString(), {
        ...playlist,
        'image': smaller,
      });
    }
  } catch (e, stackTrace) {
    logger.log('Error shrinking covers', error: e, stackTrace: stackTrace);
  }
}
