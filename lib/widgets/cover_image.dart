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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/utilities/artwork_provider.dart';

/// A cover [size] logical pixels square, from a local file or a URL: the one
/// place that decides how a cover is decoded, cropped and clipped.
///
/// It is decoded at the size it is drawn, not at full resolution. A URL is
/// fetched through [CachedNetworkImage], so it fades in over [placeholder]
/// and is kept in the same on-disk cache as every other network cover.
class CoverImage extends StatelessWidget {
  const CoverImage({
    super.key,
    required this.source,
    required this.size,
    required this.error,
    this.placeholder,
    this.borderRadius = 10,
    this.fillLetterbox = false,
    this.overlay,
  });

  /// A local file path or an http(s) URL. Empty shows [error].
  final String source;

  final double size;

  /// Shown when [source] is empty or its picture cannot be loaded.
  final Widget error;

  /// Shown while a URL loads; nothing is shown if null.
  final Widget? placeholder;

  /// How round the picture's corners are.
  final double borderRadius;

  /// Low-res YouTube 'default.jpg' thumbnails are 4:3 with the 16:9 picture
  /// in the middle and black bars above and below it, so BoxFit.cover keeps
  /// the bars visible. When set, the picture is zoomed in until the bars fall
  /// outside the square (see [letterboxZoom]).
  final bool fillLetterbox;

  /// The share of a 'default.jpg' thumbnail that the picture takes up (the
  /// rest is bars), as the zoom that leaves only the picture in the square:
  /// 90 rows of 120 px wide, 67.5 of them the picture.
  static const letterboxZoom = 90 / 67.5;

  /// Drawn over the picture, inside its rounded corners.
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    if (source.isEmpty) return error;
    final isUrl = source.startsWith('http');
    final fill = fillLetterbox && isUrl && source.contains('default.jpg');

    Widget picture(ImageProvider provider, {ImageErrorWidgetBuilder? onError}) {
      // Decoded at the size it is shown; zoomed in, a larger one, so the
      // part that shows keeps its sharpness.
      final decoded = fill ? size * letterboxZoom * (4 / 3) : size;
      Widget image = Image(
        image: ArtworkProvider.resized(provider, decoded, context),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: onError,
      );
      if (fill) image = Transform.scale(scale: letterboxZoom, child: image);
      return ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: overlay == null ? image : Stack(children: [image, overlay!]),
      );
    }

    return SizedBox.square(
      dimension: size,
      child: isUrl
          ? CachedNetworkImage(
              imageUrl: source,
              width: size,
              height: size,
              memCacheWidth: ArtworkProvider.decodeWidth(size, context),
              imageBuilder: (_, provider) => picture(provider),
              placeholder: placeholder == null ? null : (_, _) => placeholder!,
              errorWidget: (_, _, _) => error,
            )
          : picture(FileImage(File(source)), onError: (_, _, _) => error),
    );
  }
}
