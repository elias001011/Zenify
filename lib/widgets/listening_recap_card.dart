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

import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/utilities/listening_stats_utils.dart';
import 'package:musify/widgets/song_bar.dart';
import 'package:musify/widgets/top_artists_card.dart';

const _logoAsset = 'assets/icons/app_logo.png';

/// Minutes listened and top songs of a period. Wide, it splits in two: the
/// minutes and songs 1-3, then the top artist, songs 4-5 and "see all".
class ListeningRecapCard extends StatelessWidget {
  const ListeningRecapCard({
    required this.periodLabel,
    required this.minutes,
    required this.songs,
    required this.onSongTap,
    this.topArtist,
    this.onTopArtistTap,
    this.onSeeAll,
    super.key,
  });

  final String periodLabel;
  final int minutes;
  final List<Map<String, dynamic>> songs;
  final ValueChanged<int> onSongTap;
  final ListeningArtist? topArtist;
  final VoidCallback? onTopArtistTap;
  final VoidCallback? onSeeAll;

  static const double _wideWidth = 640;

  /// Whether the card takes its two-column layout at [width].
  static bool isWide(double width) => width >= _wideWidth;

  static const _leftSongs = 3;

  @override
  Widget build(BuildContext context) {
    // Measured outside the card, like callers measure it with [isWide].
    return LayoutBuilder(
      builder: (context, constraints) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: isWide(constraints.maxWidth)
              ? _buildWide(context)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context),
                    for (var i = 0; i < songs.length; i++) _buildSong(i),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildWide(BuildContext context) {
    final topArtist = this.topArtist;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              for (var i = 0; i < min(songs.length, _leftSongs); i++)
                _buildSong(i),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (topArtist != null) ...[
                _Label(context.l10n!.topArtist),
                TopArtistTile(topArtist, rank: 1, onTap: onTopArtistTap),
              ],
              for (var i = _leftSongs; i < songs.length; i++) _buildSong(i),
              if (onSeeAll != null)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: TextButton(
                    onPressed: onSeeAll,
                    child: Text(context.l10n!.seeAll),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FittedBox(
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
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          flex: 3,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: _RecapBrandHeader(periodLabel: periodLabel),
          ),
        ),
      ],
    );
  }

  Widget _buildSong(int index) => SongBar(
    key: ValueKey(songs[index]['ytid'] ?? index),
    songs[index],
    false,
    showPlayTime: true,
    rank: index + 1,
    onPlay: () => onSongTap(index),
    barPadding: const EdgeInsetsDirectional.symmetric(vertical: 10),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: TextStyle(
          color: colorScheme.onSurfaceVariant,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RecapBrandHeader extends StatelessWidget {
  const _RecapBrandHeader({required this.periodLabel});

  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fallbackMaxWidth = MediaQuery.sizeOf(context).width - 64;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : fallbackMaxWidth;

        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
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
                      style: TextStyle(
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      ' · $periodLabel',
                      maxLines: 1,
                      style: TextStyle(
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
