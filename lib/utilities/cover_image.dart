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
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:musify/main.dart' show logger;
import 'package:musify/services/local_sync_service.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/settings_manager.dart';

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

/// [shrinkCover] without holding the whole photo in memory or freezing the
/// interface: the engine decodes it already at the cover's size (a 48 MP photo
/// would be 140 MB decoded), and only the small picture is encoded, on another
/// isolate. [shrinkCover] is the fallback when the engine cannot decode it.
Future<Uint8List> shrinkCoverInBackground(Uint8List bytes) async {
  if (bytes.length <= _coverLimit) return bytes;
  try {
    final scaled = await _decodeScaled(bytes);
    if (scaled != null) {
      final jpeg = await Isolate.run(() => _encodeJpeg(scaled));
      return jpeg.length < bytes.length ? jpeg : bytes;
    }
  } catch (e, stackTrace) {
    logger.log('Decoding a cover natively', error: e, stackTrace: stackTrace);
  }
  return Isolate.run(() => shrinkCover(bytes));
}

typedef _Pixels = ({Uint8List rgba, int width, int height});

Future<_Pixels?> _decodeScaled(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final landscape = descriptor.width >= descriptor.height;
    codec = await descriptor.instantiateCodec(
      targetWidth: landscape && descriptor.width > coverSide ? coverSide : null,
      targetHeight: !landscape && descriptor.height > coverSide
          ? coverSide
          : null,
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData();
    return data == null
        ? null
        : (
            rgba: data.buffer.asUint8List(),
            width: image.width,
            height: image.height,
          );
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer.dispose();
  }
}

Uint8List _encodeJpeg(_Pixels pixels) => img.encodeJpg(
  img.Image.fromBytes(
    width: pixels.width,
    height: pixels.height,
    bytes: pixels.rgba.buffer,
    numChannels: 4,
  ),
  quality: 82,
);

/// A cover stored as a data URI, shrunk if it is large; the same string
/// otherwise.
Future<String> shrinkCoverDataUri(String dataUri) async {
  final comma = dataUri.indexOf(',');
  if (!dataUri.startsWith('data:image') || comma == -1) return dataUri;
  final bytes = base64Decode(dataUri.substring(comma + 1));
  final smaller = await shrinkCoverInBackground(bytes);
  if (smaller.length == bytes.length) return dataUri;
  return 'data:image/jpeg;base64,${base64Encode(smaller)}';
}

/// Shrinks the large covers of the playlists you made, which older versions
/// kept as picked. Each is written back through the playlists, so the other
/// devices receive the smaller one.
///
/// A write stamps the playlist with this device's clock, which wins over an
/// edit another device made and this one has not received yet: with devices
/// paired it waits until a sync has just happened.
Future<void> shrinkStoredCovers() async {
  if (localSyncEnabled.value &&
      LocalSyncService.instance.pairedDevices.value.isNotEmpty) {
    final last = localSyncLastSyncedAt.value;
    if (last == null ||
        DateTime.now().difference(last) > const Duration(minutes: 5)) {
      return;
    }
  }
  for (final listed in List.of(getUserCustomPlaylists())) {
    try {
      final cover = listed['image'];
      if (cover is! String || cover.length < _coverLimit * 4 ~/ 3) continue;
      final smaller = await shrinkCoverDataUri(cover);
      if (smaller == cover) continue;
      // The playlist may have changed while the cover was being shrunk: the
      // current one is edited, and only if its cover is still this one.
      final id = listed['ytid'].toString();
      final current = getUserCustomPlaylists()
          .where((playlist) => playlist['ytid']?.toString() == id)
          .firstOrNull;
      if (current == null || current['image'] != cover) continue;
      await replaceCustomPlaylist(id, {...current, 'image': smaller});
    } catch (e, stackTrace) {
      logger.log('Error shrinking a cover', error: e, stackTrace: stackTrace);
    }
  }
}
