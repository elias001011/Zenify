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

import 'package:material_ui/material_ui.dart';
import 'package:musify/utilities/artwork_provider.dart';
import 'package:musify/widgets/app_logo.dart';

/// The cover of one of Zenify's own playlists, drawn from what it holds
/// right now: up to four of its artworks, the Zenify logo and its title. It
/// changes with the playlist, so there is nothing to edit.
class ZenifyCover extends StatelessWidget {
  const ZenifyCover(this.playlist, {super.key, required this.size});

  final Map playlist;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final covers = [
      for (final cover in playlist['covers'] as List? ?? const [])
        if (cover is String && cover.isNotEmpty) cover,
    ];
    final tile = covers.length >= 4 ? size / 2 : size;

    // Sized outright: left to its own aspect, a wide thumbnail would stop
    // short of its cell and show the background beside it.
    Widget art(String url) => Image(
      image: ArtworkProvider.thumbnail(url, tile, context),
      width: tile,
      height: tile,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) =>
          ColoredBox(color: theme.colorScheme.surfaceContainerHigh),
    );

    return SizedBox.square(
      dimension: size,
      // Treat the composed cover like an image: weighted carousels crop it
      // as a card narrows, without reflowing its title or adding a scrollable.
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Under the artworks while they load, and alone without any.
              ColoredBox(color: theme.colorScheme.primaryContainer),
              if (covers.isEmpty)
                const SizedBox.shrink()
              else if (covers.length < 4)
                art(covers.first)
              else
                Column(
                  children: [
                    for (var row = 0; row < 2; row++)
                      Expanded(
                        child: Row(
                          children: [
                            for (var column = 0; column < 2; column++)
                              Expanded(child: art(covers[row * 2 + column])),
                          ],
                        ),
                      ),
                  ],
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.1),
                      Colors.black.withValues(alpha: 0.75),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(size * 0.07),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppLogo(size: size * 0.14, color: Colors.white),
                    const Spacer(),
                    Text(
                      playlist['title']?.toString() ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: size * 0.1,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
