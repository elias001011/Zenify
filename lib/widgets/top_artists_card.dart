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

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/listening_stats_utils.dart';
import 'package:musify/utilities/mediaitem.dart';
import 'package:musify/widgets/listening_recap_card.dart';
import 'package:musify/widgets/song_artwork.dart';

/// The most listened artists of a period, ranked.
class TopArtistsCard extends StatelessWidget {
  const TopArtistsCard({required this.artists, this.periodLabel, super.key});

  final List<ListeningArtist> artists;

  /// Names the period on the card, for sharing it as an image.
  final String? periodLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (periodLabel case final label?) ...[
              RecapBrandHeader(periodLabel: label),
              const SizedBox(height: 12),
            ],
            Text(
              context.l10n!.topArtists,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            for (var i = 0; i < artists.length; i++)
              TopArtistTile(artists[i], rank: i + 1),
          ],
        ),
      ),
    );
  }
}

/// One listened artist: round artwork from their top song, name and time.
class TopArtistTile extends StatelessWidget {
  const TopArtistTile(this.artist, {this.rank, this.onTap, super.key});

  final ListeningArtist artist;
  final int? rank;

  /// Defaults to opening the artist's page.
  final VoidCallback? onTap;

  static const double _artworkSize = 52;

  void _openArtist(BuildContext context) {
    final destination = NavigationManager.artistDestination(
      context,
      name: artist.name,
      sourceSongId: artist.topSong['ytid']?.toString() ?? '',
    );
    if (destination != null) {
      context.push(destination.path, extra: destination.extra);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rank = this.rank;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      // Artist pages need YouTube.
      onTap: onTap ?? (offlineMode.value ? null : () => _openArtist(context)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            if (rank != null) ...[
              SizedBox(
                width: 28,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            SongArtworkWidget(
              size: _artworkSize,
              borderRadius: _artworkSize / 2,
              metadata: mapToMediaItem(artist.topSong),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n!.artistListeningSummary(
                      artist.seconds ~/ 60,
                      artist.songCount,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
