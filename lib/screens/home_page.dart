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
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/moods/moods_preferences.dart';
import 'package:musify/services/moods/moods_service.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/async_loader.dart';
import 'package:musify/utilities/listening_stats_utils.dart';
import 'package:musify/widgets/announcement_box.dart';
import 'package:musify/widgets/floating_island.dart';
import 'package:musify/widgets/glow_row.dart';
import 'package:musify/widgets/listening_recap_card.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:musify/widgets/moods_row.dart';
import 'package:musify/widgets/playlist_cube.dart';
import 'package:musify/widgets/recommended_songs_section.dart';
import 'package:musify/widgets/section_header.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Future<List> _suggestedPlaylistsFuture;
  late Future<List> _recommendedSongsFuture;
  Stream<List<Map>>? _zenifyPlaylists;
  DateTime _zenifyLoadedAt = DateTime.now();
  late final AppLifecycleListener _lifecycle;
  final _moodsInputs = Listenable.merge([
    moodsEnabled,
    offlineMode,
    moodsTuning,
  ]);

  @override
  void initState() {
    super.initState();
    _loadZenifyPlaylists();
    _moodsInputs.addListener(_onMoodsToggled);
    _lifecycle = AppLifecycleListener(onResume: _refreshIfStale);
    _suggestedPlaylistsFuture = getPlaylists(
      playlistsNum: suggestedPlaylistsNumber,
    );
    _recommendedSongsFuture = getRecommendedSongs();
    externalRecommendations.addListener(_refreshRecommendedSongs);
  }

  @override
  void dispose() {
    externalRecommendations.removeListener(_refreshRecommendedSongs);
    _moodsInputs.removeListener(_onMoodsToggled);
    _lifecycle.dispose();
    super.dispose();
  }

  bool get _showsMoods => moodsEnabled.value && !offlineMode.value;

  void _loadZenifyPlaylists() {
    _zenifyLoadedAt = DateTime.now();
    _zenifyPlaylists = _showsMoods ? moodsService.playlists() : null;
  }

  void _onMoodsToggled() {
    if (mounted) setState(_loadZenifyPlaylists);
  }

  /// Back in the app after a while, the playlist of the moment or of the
  /// day may have changed; the rest come from the cache.
  void _refreshIfStale() {
    final now = DateTime.now();
    final crossedSlot =
        now.hour ~/ 4 != _zenifyLoadedAt.hour ~/ 4 ||
        !DateUtils.isSameDay(now, _zenifyLoadedAt);
    if (crossedSlot) _onMoodsToggled();
  }

  void _refreshRecommendedSongs() {
    if (!mounted) return;
    setState(() {
      _recommendedSongsFuture = getRecommendedSongs();
    });
  }

  @override
  Widget build(BuildContext context) {
    final playlistHeight = MediaQuery.sizeOf(context).height * 0.25 / 1.1;
    return IslandScaffold(
      title: appName,
      body: SingleChildScrollView(
        padding: withIslandInset(context, commonSingleChildScrollViewPadding),
        child: Column(
          children: [
            ValueListenableBuilder<String?>(
              valueListenable: announcementURL,
              builder: (_, _url, __) {
                if (_url == null) return const SizedBox.shrink();
                final isSponsorshipAnnouncement = isSponsorshipAnnouncementUrl(
                  _url,
                );
                final _message = isSponsorshipAnnouncement
                    ? context.l10n!.sponsorProject
                    : context.l10n!.newAnnouncement;
                final _icon = isSponsorshipAnnouncement
                    ? FluentIcons.heart_24_filled
                    : FluentIcons.megaphone_24_filled;

                return AnnouncementBox(
                  message: _message,
                  url: _url,
                  icon: _icon,
                  onDismiss: () async {
                    announcementURL.value = null;
                  },
                );
              },
            ),
            _buildSuggestedPlaylists(playlistHeight),
            _buildSuggestedPlaylists(playlistHeight, showOnlyLiked: true),
            _buildCurrentMonthRecapSection(),
            if (_showsMoods) ...[
              const MoodsRow(),
              _buildZenifyPlaylists(playlistHeight),
            ],
            _buildRecommendedSongsSection(),
            const MiniPlayerBottomSpace(),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestedPlaylists(
    double playlistHeight, {
    bool showOnlyLiked = false,
  }) {
    if (showOnlyLiked) {
      return ValueListenableBuilder<List<Map>>(
        valueListenable: userLikedPlaylists,
        builder: (_, likedPlaylists, __) => _buildSuggestedPlaylistsSection(
          playlistHeight,
          likedPlaylists
              .where((playlist) => !isArtistPlaylist(playlist))
              .take(recommendedCubesNumber)
              .toList(),
          showOnlyLiked: true,
        ),
      );
    }

    return AsyncLoader<List<dynamic>>(
      future: _suggestedPlaylistsFuture,
      builder: (context, playlists) =>
          _buildSuggestedPlaylistsSection(playlistHeight, playlists),
    );
  }

  Widget _buildZenifyPlaylists(double playlistHeight) {
    // They show up as they are made rather than holding a spinner on Home.
    return StreamBuilder<List<Map>>(
      key: ValueKey(_zenifyPlaylists),
      stream: _zenifyPlaylists,
      builder: (context, snapshot) => _buildSuggestedPlaylistsSection(
        playlistHeight,
        snapshot.data ?? const [],
        title: context.l10n!.madeForYou,
        icon: FluentIcons.person_star_24_filled,
      ),
    );
  }

  Widget _buildSuggestedPlaylistsSection(
    double playlistHeight,
    List<dynamic> playlists, {
    bool showOnlyLiked = false,
    String? title,
    IconData? icon,
  }) {
    if (playlists.isEmpty) return const SizedBox.shrink();

    final sectionTitle =
        title ??
        (showOnlyLiked
            ? context.l10n!.backToFavorites
            : context.l10n!.suggestedPlaylists);
    final itemsNumber = playlists.length;
    final isLargeScreen = MediaQuery.of(context).size.width > 480;

    return Column(
      children: [
        SectionHeader(
          title: sectionTitle,
          icon:
              icon ??
              (showOnlyLiked
                  ? FluentIcons.heart_24_filled
                  : FluentIcons.list_24_filled),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: playlistHeight),
          child: isLargeScreen
              ? _buildHorizontalList(playlists, itemsNumber, playlistHeight)
              : _buildCarouselView(playlists, itemsNumber, playlistHeight),
        ),
      ],
    );
  }

  Widget _buildHorizontalList(
    List<dynamic> playlists,
    int itemCount,
    double height,
  ) {
    return GlowRow(
      sources: [
        for (var i = 0; i < itemCount; i++) playlists[i]['image']?.toString(),
      ],
      itemExtent: height + 16,
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: GestureDetector(
            onTap: () => context.push(
              '/home/playlist/${Uri.encodeComponent('${playlist['ytid']}')}',
            ),
            child: PlaylistCube(playlist, size: height),
          ),
        );
      },
    );
  }

  Widget _buildCarouselView(
    List<dynamic> playlists,
    int itemCount,
    double height,
  ) {
    return GlowCarousel(
      sources: [
        for (var i = 0; i < itemCount; i++) playlists[i]['image']?.toString(),
      ],
      onTap: (index) => context.push(
        '/home/playlist/${Uri.encodeComponent('${playlists[index]['ytid']}')}',
      ),
      itemBuilder: (context, index) =>
          PlaylistCube(playlists[index], size: height * 2),
    );
  }

  Widget _buildRecommendedSongsSection() {
    return AsyncLoader<List<dynamic>>(
      future: _recommendedSongsFuture,
      builder: (context, data) {
        if (data.isEmpty) return const SizedBox.shrink();
        return _buildRecommendedForYouSection(context, data);
      },
    );
  }

  Widget _buildCurrentMonthRecapSection() {
    return ValueListenableBuilder<bool>(
      valueListenable: wrappedEnabled,
      builder: (_, isEnabled, __) {
        if (!isEnabled) return const SizedBox.shrink();

        final currentMonthKey = listeningStatsMonthKey(DateTime.now());
        final monthStats = listeningStatsService.monthStats(currentMonthKey);
        final songs = listeningStatsService.monthTopSongs(currentMonthKey);
        final displayMinutes = monthDisplayMinutes(monthStats);
        if (displayMinutes <= 0 && songs.isEmpty) {
          return const SizedBox.shrink();
        }

        final previewSongs = songs.take(wrappedShareSongsLimit).toList();
        final periodLabel = formatMonthPeriodLabel(
          Localizations.localeOf(context),
          currentMonthKey,
        );

        return Column(
          children: [
            SectionHeader(
              title: context.l10n!.timeMachine,
              icon: FluentIcons.data_trending_24_filled,
            ),
            ListeningRecapCards(
              periodLabel: periodLabel,
              minutes: displayMinutes,
              songs: previewSongs,
              onSongTap: (index) => _playRecapSongs(previewSongs, index),
              topArtist: listeningStatsService
                  .monthTopArtists(currentMonthKey)
                  .firstOrNull,
              onMinutesTap: () =>
                  context.push(NavigationManager.timeMachinePath),
              onArtistTap: () => context.push(NavigationManager.topArtistsPath),
            ),
            RecapSeeAllButton(
              onPressed: () => context.push(NavigationManager.timeMachinePath),
            ),
          ],
        );
      },
    );
  }

  Future<void> _playRecapSongs(
    List<Map<String, dynamic>> songs,
    int index,
  ) async {
    if (songs.isEmpty) return;
    await audioHandler.playPlaylistSong(
      playlist: {'title': context.l10n!.timeMachine, 'list': songs},
      songIndex: index,
    );
  }

  Widget _buildRecommendedForYouSection(
    BuildContext context,
    List<dynamic> data,
  ) {
    return RecommendedSongsSection(
      title: context.l10n!.recommendedForYou,
      songs: data,
      listKeyPrefix: 'home_recommended',
    );
  }
}
