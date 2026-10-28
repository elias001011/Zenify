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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/utilities/listening_stats_utils.dart';
import 'package:musify/utilities/mediaitem.dart';
import 'package:musify/widgets/song_artwork.dart';
import 'package:musify/widgets/song_bar.dart';

const _logoAsset = 'assets/icons/app_logo.png';

/// A listening period in cards: minutes and the top artist side by side,
/// then the top songs.
class ListeningRecapCards extends StatelessWidget {
  const ListeningRecapCards({
    required this.periodLabel,
    required this.minutes,
    required this.songs,
    required this.onSongTap,
    this.topArtist,
    this.onMinutesTap,
    this.onArtistTap,
    super.key,
  });

  final String periodLabel;
  final int minutes;
  final List<Map<String, dynamic>> songs;
  final ValueChanged<int> onSongTap;
  final ListeningArtist? topArtist;
  final VoidCallback? onMinutesTap;
  final VoidCallback? onArtistTap;

  @override
  Widget build(BuildContext context) {
    final topArtist = this.topArtist;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _RecapCard(
                  onTap: onMinutesTap,
                  child: _MinutesContent(
                    minutes: minutes,
                    periodLabel: periodLabel,
                  ),
                ),
              ),
              if (topArtist != null)
                Expanded(
                  child: _RecapCard(
                    onTap: onArtistTap,
                    child: _ArtistContent(topArtist),
                  ),
                ),
            ],
          ),
        ),
        if (songs.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                children: [
                  for (var i = 0; i < songs.length; i++)
                    SongBar(
                      key: ValueKey(songs[i]['ytid'] ?? i),
                      songs[i],
                      false,
                      showPlayTime: true,
                      rank: i + 1,
                      onPlay: () => onSongTap(i),
                      barPadding: const EdgeInsetsDirectional.symmetric(
                        vertical: 10,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// "See all" under [ListeningRecapCards], outside what a shared recap shows.
class RecapSeeAllButton extends StatelessWidget {
  const RecapSeeAllButton({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: onPressed,
          icon: const Icon(FluentIcons.arrow_right_24_regular),
          iconAlignment: IconAlignment.end,
          label: Text(context.l10n!.seeAll),
        ),
      ),
    );
  }
}

class _RecapCard extends StatelessWidget {
  const _RecapCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );
  }
}

class _MinutesContent extends StatelessWidget {
  const _MinutesContent({required this.minutes, required this.periodLabel});

  final int minutes;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        RecapBrandHeader(periodLabel: periodLabel),
        const SizedBox(height: 14),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            '$minutes',
            maxLines: 1,
            style: TextStyle(
              color: colorScheme.primary,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          context.l10n!.minutesListened,
          maxLines: 2,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ArtistContent extends StatelessWidget {
  const _ArtistContent(this.artist);

  final ListeningArtist artist;

  static const double _artworkSize = 56;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          context.l10n!.topArtist,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        SongArtworkWidget(
          size: _artworkSize,
          borderRadius: _artworkSize / 2,
          metadata: mapToMediaItem(artist.topSong),
        ),
        const SizedBox(height: 10),
        Text(
          artist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
          ),
        ),
        Text(
          context.l10n!.artistListeningSummary(
            artist.seconds ~/ 60,
            artist.songCount,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// The app and the period, so a shared card says where and when it is from.
class RecapBrandHeader extends StatelessWidget {
  const RecapBrandHeader({required this.periodLabel, super.key});

  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = TextStyle(
      color: colorScheme.onSecondaryContainer,
      fontWeight: FontWeight.w600,
      fontSize: 12,
    );

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ImageIcon(
                const AssetImage(_logoAsset),
                size: 16,
                color: colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                appName,
                maxLines: 1,
                style: style.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(' · $periodLabel', maxLines: 1, style: style),
            ],
          ),
        ),
      ),
    );
  }
}
