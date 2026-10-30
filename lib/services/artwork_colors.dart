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

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';

/// The most vivid colour of an artwork, for the dynamic background.
///
/// Artworks are read at 24×24, so this costs next to nothing, and every
/// result (including "no colour") is cached for the session.
class ArtworkColors {
  ArtworkColors._();

  static const _sampleSize = 24;
  static const _maxEntries = 400;

  static final _cache = <String, Color?>{};
  static final _pending = <String, Future<Color?>>{};

  static bool isCached(String source) => _cache.containsKey(source);

  static Color? cached(String source) => _cache[source];

  /// [source] is a network URL or a local file path.
  static Future<Color?> of(String source) {
    if (_cache.containsKey(source)) return Future.value(_cache[source]);
    return _pending[source] ??= _extract(source).then((color) {
      _pending.remove(source);
      if (_cache.length >= _maxEntries) _cache.remove(_cache.keys.first);
      return _cache[source] = color;
    });
  }

  static Future<Color?> _extract(String source) async {
    try {
      final provider = source.startsWith('http')
          ? CachedNetworkImageProvider(source) as ImageProvider
          : FileImage(File(source));
      final sample = ResizeImage(
        provider,
        width: _sampleSize,
        height: _sampleSize,
      );
      final image = await _load(sample);
      // The tiny sample would only crowd real artworks out of the cache.
      unawaited(sample.evict());
      try {
        final data = await image.toByteData();
        return data == null ? null : vividColor(data.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    }
  }

  static Future<ui.Image> _load(ImageProvider provider) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        completer.complete(info.image.clone());
        info.dispose();
      },
      onError: (error, stackTrace) {
        stream.removeListener(listener);
        completer.completeError(error, stackTrace);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  /// Averages the RGBA [pixels] weighted by how vivid each one is, then
  /// lifts the result so it reads as a glow on black or white.
  @visibleForTesting
  static Color? vividColor(List<int> pixels) {
    var r = 0.0, g = 0.0, b = 0.0, total = 0.0;
    for (var i = 0; i + 3 < pixels.length; i += 4) {
      if (pixels[i + 3] < 128) continue;
      final red = pixels[i], green = pixels[i + 1], blue = pixels[i + 2];
      final high = red > green
          ? (red > blue ? red : blue)
          : (green > blue ? green : blue);
      final low = red < green
          ? (red < blue ? red : blue)
          : (green < blue ? green : blue);
      final delta = high - low;
      // saturation² × value, without constructing an HSV object per pixel.
      final weight = (high == 0 ? 0 : delta * delta / (high * 255)) + 0.002;
      r += pixels[i] * weight;
      g += pixels[i + 1] * weight;
      b += pixels[i + 2] * weight;
      total += weight;
    }
    if (total == 0) return null;
    final average = HSVColor.fromColor(
      Color.fromARGB(
        255,
        (r / total).round(),
        (g / total).round(),
        (b / total).round(),
      ),
    );
    // Grey artwork has no colour worth spreading.
    if (average.saturation < 0.12) return null;
    return average
        .withSaturation(average.saturation.clamp(0.45, 0.9))
        .withValue(average.value.clamp(0.6, 0.95))
        .toColor();
  }
}
