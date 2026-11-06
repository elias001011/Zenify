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
import 'package:musify/services/moods/mix_engine.dart';
import 'package:musify/services/moods/moods_preferences.dart';
import 'package:musify/services/moods/moods_service.dart';
import 'package:musify/services/moods/taste.dart';
import 'package:musify/widgets/artwork_glow.dart';
import 'package:musify/widgets/floating_island.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:musify/widgets/music_list_surface.dart';
import 'package:musify/widgets/section_header.dart';
import 'package:musify/widgets/spinner.dart';
import 'package:musify/widgets/top_artists_card.dart';

/// "Tune the Moods": how much to discover, the genres the user listens to
/// and the artists that may come up, as Deezer's "Tune your Flow". What is
/// chosen here is kept in the library (see [MoodsTuning]); the genres and
/// artists themselves come from what the user listens to.
class MoodsTuningPage extends StatefulWidget {
  const MoodsTuningPage({super.key});

  @override
  State<MoodsTuningPage> createState() => _MoodsTuningPageState();
}

class _MoodsTuningPageState extends State<MoodsTuningPage> {
  late final Taste _taste = moodsService.taste(withBlocked: true);
  late final Future<List<DetectedGenre>> _genres = moodsService
      .detectedGenres();

  /// One of the user's songs by each artist, for its avatar: the best ranked.
  late final Map<String, Map> _artistSong = {
    for (final seed in _taste.seeds.reversed)
      artistKey(seed.song['artist']): seed.song,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    return IslandScaffold(
      background: const PageGlow(source: null, cacheKey: 'moods_tuning_page'),
      title: l10n.moodsTuning,
      globalSearch: false,
      actions: [
        ValueListenableBuilder<MoodsTuning>(
          valueListenable: moodsTuning,
          builder: (context, tuning, _) => IconButton(
            icon: const Icon(FluentIcons.arrow_reset_24_regular),
            tooltip: l10n.reset,
            onPressed: tuning.isDefault
                ? null
                : () => setMoodsTuning(const MoodsTuning()),
          ),
        ),
      ],
      body: ReadablePadding(
        padding: commonSingleChildScrollViewPadding,
        builder: (context, padding) => SingleChildScrollView(
          padding: padding,
          child: ValueListenableBuilder<MoodsTuning>(
            valueListenable: moodsTuning,
            builder: (context, tuning, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDiscovery(context, tuning),
                _buildGenres(context, tuning),
                _buildArtists(context, tuning),
                const SizedBox(height: 20),
                const MiniPlayerBottomSpace(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDiscovery(BuildContext context, MoodsTuning tuning) {
    final l10n = context.l10n!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: l10n.moodsTuningDiscovery,
          icon: FluentIcons.compass_northwest_24_filled,
        ),
        SegmentedButton<Discovery>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: Discovery.familiar,
              label: Text(l10n.discoveryFamiliar, textAlign: TextAlign.center),
            ),
            ButtonSegment(
              value: Discovery.balanced,
              label: Text(l10n.discoveryBalanced, textAlign: TextAlign.center),
            ),
            ButtonSegment(
              value: Discovery.adventurous,
              label: Text(
                l10n.discoveryAdventurous,
                textAlign: TextAlign.center,
              ),
            ),
          ],
          selected: {tuning.discovery},
          onSelectionChanged: (choice) =>
              setMoodsTuning(tuning.copyWith(discovery: choice.single)),
        ),
      ],
    );
  }

  Widget _buildGenres(BuildContext context, MoodsTuning tuning) {
    final l10n = context.l10n!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: l10n.moodsTuningGenres,
          icon: FluentIcons.music_note_2_24_filled,
        ),
        FutureBuilder<List<DetectedGenre>>(
          future: _genres,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Spinner(),
                    const SizedBox(height: 12),
                    Text(
                      l10n.moodsTuningReading,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }
            final genres = snapshot.data ?? const [];
            if (genres.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  l10n.moodsTuningGenresEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.maxWidth / 220).floor().clamp(
                  2,
                  4,
                );
                final width =
                    (constraints.maxWidth - 12 * (columns - 1)) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final genre in genres)
                      SizedBox(
                        width: width,
                        child: _GenreCard(
                          genre: genre,
                          names: [
                            for (final key in genre.artists.take(3))
                              _taste.artistNames[key] ?? key,
                          ],
                          songs: [
                            for (final key in genre.artists)
                              if (_artistSong[key] case final song?) song,
                          ].take(3).toList(),
                          included: !tuning.excludedGenres.contains(
                            genre.title,
                          ),
                          onChanged: (included) => setMoodsTuning(
                            tuning.copyWith(
                              excludedGenres: included
                                  ? ({...tuning.excludedGenres}
                                      ..remove(genre.title))
                                  : {...tuning.excludedGenres, genre.title},
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  void _setArtistAllowed(MoodsTuning tuning, String key, bool allowed) =>
      setMoodsTuning(
        tuning.copyWith(
          blockedArtists: allowed
              ? ({...tuning.blockedArtists}..remove(key))
              : {...tuning.blockedArtists, key},
        ),
      );

  Widget _buildArtists(BuildContext context, MoodsTuning tuning) {
    final keys = {
      ..._taste.artists.keys.take(20),
      ...tuning.blockedArtists,
    }.toList();
    if (keys.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: context.l10n!.moodsTuningArtists,
          icon: FluentIcons.person_24_filled,
        ),
        MusicListSurface(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                for (final key in keys)
                  ArtistTile(
                    artwork: ArtistAvatar(_artistSong[key]),
                    name: _taste.artistNames[key] ?? key,
                    struck: tuning.blockedArtists.contains(key),
                    trailing: Switch(
                      value: !tuning.blockedArtists.contains(key),
                      onChanged: (allowed) =>
                          _setArtistAllowed(tuning, key, allowed),
                    ),
                    onTap: () => _setArtistAllowed(
                      tuning,
                      key,
                      tuning.blockedArtists.contains(key),
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

class _GenreCard extends StatelessWidget {
  const _GenreCard({
    required this.genre,
    required this.names,
    required this.songs,
    required this.included,
    required this.onChanged,
  });

  final DetectedGenre genre;
  final List<String> names;
  final List<Map> songs;
  final bool included;
  final ValueChanged<bool> onChanged;

  static const _avatar = 52.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MusicListSurface(
      color: included
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: () => onChanged(!included),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: _avatar,
                child: Stack(
                  children: [
                    for (var i = 0; i < (songs.isEmpty ? 1 : songs.length); i++)
                      Positioned(
                        left: i * _avatar * 0.62,
                        child: ArtistAvatar(songs.isEmpty ? null : songs[i]),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                genre.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                names.join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Switch(value: included, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}
