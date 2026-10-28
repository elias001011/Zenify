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
 */

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/artwork_glow.dart';
import 'package:musify/widgets/playlist_hero_artwork.dart';

/// The top of a playlist, album or artist page: the artwork, glowing into
/// the page, and the title, which the island shows once it scrolls away.
class PlaylistSliverAppBar extends StatelessWidget {
  const PlaylistSliverAppBar({
    super.key,
    required this.title,
    required this.playlist,
    this.cubeIcon = FluentIcons.text_bullet_list_24_filled,
  });

  final String title;
  final Map playlist;
  final IconData cubeIcon;

  static double _artworkHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width > size.height ? 260 : 220;
  }

  /// Where the island starts fading the title in.
  static double titleFadeStart(BuildContext context) =>
      _artworkHeight(context) + 16;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SliverToBoxAdapter(
      child: Column(
        children: [
          SizedBox(height: MediaQuery.paddingOf(context).top),
          ArtworkGlow(
            source: playlist['image']?.toString(),
            child: SizedBox(
              height: _artworkHeight(context),
              width: double.infinity,
              child: Center(
                child: PlaylistHeroArtwork(playlist, cubeIcon: cubeIcon),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
