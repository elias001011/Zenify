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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/database/radio_stations.db.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/models/radio_model.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/library_search.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/widgets/artist_bar.dart';
import 'package:musify/widgets/confirmation_dialog.dart';
import 'package:musify/widgets/custom_bar.dart';
import 'package:musify/widgets/custom_search_bar.dart';
import 'package:musify/widgets/floating_island.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:musify/widgets/playlist_bar.dart';
import 'package:musify/widgets/radio_station_card.dart';
import 'package:musify/widgets/section_title.dart';
import 'package:musify/widgets/song_bar.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  _SearchPageState createState() => _SearchPageState();
}

// Global ValueNotifier for search history to make it reactive
final ValueNotifier<List> searchHistoryNotifier = ValueNotifier<List>(
  Hive.box('user').get('searchHistory', defaultValue: []),
);

void reloadSearchHistoryFromStorage() {
  searchHistoryNotifier.value = Hive.box('user')
      .get('searchHistory', defaultValue: []);
}

/// Bumped by the search shortcut; the page focuses its field once visible.
final searchFocusRequest = ValueNotifier<int>(0);
int _handledSearchFocusRequest = 0;

void requestSearchFocus() => searchFocusRequest.value++;

/// A query from the island's search shortcut, run once the page is shown.
final pendingSearchQuery = ValueNotifier<String?>(null);

void openSearch(String query) {
  pendingSearchQuery.value = query;
  NavigationManager.router.go(NavigationManager.searchPath);
}

const LibraryMatches _noLibraryMatches = (
  artists: [],
  playlists: [],
  songs: [],
);

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchBar = TextEditingController();
  final FocusNode _inputNode = FocusNode();
  final ValueNotifier<bool> _fetchingSongs = ValueNotifier(false);
  int maxSongsInList = 15;
  List<dynamic> _songsSearchResult = [];
  List<Map<String, dynamic>> _artistsSearchResult = [];
  List<dynamic> _albumsSearchResult = [];
  List<dynamic> _playlistsSearchResult = [];
  List<RadioStation> _radioStationsSearchResult = [];
  LibraryMatches _libraryResult = _noLibraryMatches;
  List<String> _suggestionsList = [];
  Timer? _debounce;
  int _latestSuggestionRequest = 0;
  int _latestSearchRequest = 0;

  @override
  void initState() {
    super.initState();
    searchFocusRequest.addListener(_focusOnRequest);
    pendingSearchQuery.addListener(_runPendingSearch);
    WidgetsBinding.instance.addPostFrameCallback((_) => _runPendingSearch());
    // A request made from another tab arrives before this page mounts.
    if (searchFocusRequest.value != _handledSearchFocusRequest) {
      _focusOnRequest();
    }
  }

  void _runPendingSearch() {
    final query = pendingSearchQuery.value;
    if (query == null || !mounted) return;
    pendingSearchQuery.value = null;
    _submitSearch(query);
  }

  void _focusOnRequest() {
    _handledSearchFocusRequest = searchFocusRequest.value;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputNode.requestFocus();
    });
  }

  Future<void> _submitSearch([String? query]) async {
    if (query != null) {
      _searchBar.text = query;
      _searchBar.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchBar.text.length),
      );
    }

    _latestSuggestionRequest++;
    _debounce?.cancel();
    _suggestionsList = [];
    if (mounted) setState(() {});

    await search();
    _inputNode.unfocus();
  }

  @override
  void dispose() {
    searchFocusRequest.removeListener(_focusOnRequest);
    pendingSearchQuery.removeListener(_runPendingSearch);
    _searchBar.dispose();
    _inputNode.dispose();
    _fetchingSongs.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> search() async {
    final query = _searchBar.text.trim();
    final requestId = ++_latestSearchRequest;

    if (query.isEmpty) {
      _songsSearchResult = [];
      _artistsSearchResult = [];
      _albumsSearchResult = [];
      _playlistsSearchResult = [];
      _radioStationsSearchResult = [];
      _libraryResult = _noLibraryMatches;
      _suggestionsList = [];
      _fetchingSongs.value = false;
      if (mounted) setState(() {});
      return;
    }
    _fetchingSongs.value = true;

    final offline = offlineMode.value;
    _libraryResult = searchLibrary(query, offlineOnly: offline);
    // What the library holds shows at once and stays first in each section.
    _songsSearchResult = libraryFirst(_libraryResult.songs, const []);
    _artistsSearchResult = [];
    _albumsSearchResult = libraryFirst(_libraryAlbums(true), const []);
    _playlistsSearchResult = libraryFirst(_libraryAlbums(false), const []);
    _radioStationsSearchResult = offline
        ? []
        : radioStationsDB
              .where(
                (station) =>
                    station.name.toLowerCase().contains(query.toLowerCase()) ||
                    (station.genre?.toLowerCase().contains(
                          query.toLowerCase(),
                        ) ??
                        false),
              )
              .toList();
    if (mounted) setState(() {});

    if (!searchHistoryNotifier.value.contains(query)) {
      final updatedHistory = List.from(searchHistoryNotifier.value)
        ..insert(0, query);
      searchHistoryNotifier.value = updatedHistory;
      unawaited(addOrUpdateData<List>('user', 'searchHistory', updatedHistory));
    }

    // Offline, the library is all there is to search.
    if (offline) {
      _fetchingSongs.value = false;
      if (mounted) setState(() {});
      return;
    }

    try {
      final artistsFuture = searchArtists(query);
      Future<List> guarded(String what, Future<List> Function() fetch) async {
        try {
          return await fetch().timeout(const Duration(seconds: 15));
        } catch (e, stackTrace) {
          logger.log(
            'Error while searching online $what',
            error: e,
            stackTrace: stackTrace,
          );
          return const [];
        }
      }

      // Two steps, each at once: songs and artists, the top of the page,
      // then albums and playlists below them, which moves nothing above.
      final top = Future.wait([
        guarded('songs', () => _fetchSongs(query, artistsFuture)),
        guarded('artists', () => artistsFuture),
      ]);
      final rest = Future.wait([
        guarded('albums', () => getPlaylists(query: query, type: 'album')),
        guarded(
          'playlists',
          () => getPlaylists(query: query, type: 'playlist'),
        ),
      ]);

      final [songs, artists] = await top;
      if (!mounted || requestId != _latestSearchRequest) return;
      setState(() {
        _songsSearchResult = libraryFirst(
          _libraryResult.songs,
          songs,
          known: librarySongsById(),
        );
        _artistsSearchResult = _newArtists(artists)
            .map(Map<String, dynamic>.from)
            .toList();
      });

      final [albums, playlists] = await rest;
      if (!mounted || requestId != _latestSearchRequest) return;
      setState(() {
        _albumsSearchResult = libraryFirst(_libraryAlbums(true), albums);
        _playlistsSearchResult = libraryFirst(_libraryAlbums(false), playlists);
      });
    } catch (e, stackTrace) {
      logger.log(
        'Error while searching online songs',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      if (requestId == _latestSearchRequest) {
        _fetchingSongs.value = false;
        if (mounted) setState(() {});
      }
    }
  }

  /// The library's matching albums, or its other playlists.
  List<Map> _libraryAlbums(bool albums) => [
    for (final playlist in _libraryResult.playlists)
      if ((playlist['isAlbum'] == true) == albums) playlist,
  ];

  /// Whether [playlist] came from the library, which opens it as it is there.
  bool _inLibrary(Map playlist) =>
      _libraryResult.playlists.any((item) => identical(item, playlist));

  /// Online [artists] the library section does not already show, by id or
  /// name.
  List<Map> _newArtists(List artists) {
    final shown = _libraryResult.artists;
    final ids = {for (final item in shown) item['ytid']?.toString()};
    final names = {
      for (final item in shown) item['title']?.toString().toLowerCase(),
    };
    return [
      for (final item in artists.whereType<Map>())
        if (!ids.contains(item['ytid']?.toString()) &&
            !names.contains(item['title']?.toString().toLowerCase()))
          item,
    ];
  }

  /// Songs for [query]; when it finds none but names an artist, that
  /// artist's songs.
  Future<List> _fetchSongs(
    String query,
    Future<List<Map<String, dynamic>>> artistsFuture,
  ) async {
    final songs = await fetchSongsList(query);
    if (songs.isNotEmpty) return songs;
    final artists = await artistsFuture;
    final artistName = artists.firstOrNull?['title']?.toString().trim();
    if (artistName == null || artistName.isEmpty) return const [];

    final fallbackQueries = <String>{
      if (artistName.toLowerCase() != query.trim().toLowerCase()) artistName,
      '$artistName songs',
      '$artistName music',
    };

    for (final fallbackQuery in fallbackQueries) {
      final songs = await fetchSongsList(fallbackQuery);
      if (songs.isNotEmpty) return songs;
    }

    return [];
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return IslandScaffold(
      title: context.l10n!.search,
      globalSearch: false,
      body: SingleChildScrollView(
        padding: withIslandInset(context, commonSingleChildScrollViewPadding),
        child: Column(
          children: <Widget>[
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 600;
                final bar = ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isWide ? 600 : double.infinity,
                  ),
                  child: CustomSearchBar(
                    loadingProgressNotifier: _fetchingSongs,
                    controller: _searchBar,
                    focusNode: _inputNode,
                    labelText: '${context.l10n!.search}...',
                    onChanged: (value) {
                      // debounce suggestions to avoid rapid API calls
                      _debounce?.cancel();
                      final query = value;
                      final requestId = ++_latestSuggestionRequest;

                      // An emptied field goes back to the search history, and
                      // the history only shows while nothing has been found
                      // yet. Dropping the suggestions is not enough: the
                      // results of the last search have to go with them.
                      if (query.isEmpty) {
                        unawaited(search());
                        return;
                      }
                      // Suggestions come from YouTube.
                      if (offlineMode.value) return;

                      _debounce = Timer(
                        const Duration(milliseconds: 300),
                        () async {
                          final searchSuggestions = await getSearchSuggestions(
                            query,
                          );

                          if (!mounted ||
                              requestId != _latestSuggestionRequest ||
                              _searchBar.text != query) {
                            return;
                          }

                          _suggestionsList = List<String>.from(
                            searchSuggestions,
                          );
                          if (mounted) setState(() {});
                        },
                      );
                    },
                    onSubmitted: (String value) {
                      _submitSearch();
                    },
                  ),
                );
                if (isWide) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [bar],
                  );
                } else {
                  return bar;
                }
              },
            ),

            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child:
                  (_suggestionsList.isNotEmpty ||
                      (_songsSearchResult.isEmpty &&
                          _libraryResult.artists.isEmpty &&
                          _artistsSearchResult.isEmpty &&
                          _albumsSearchResult.isEmpty &&
                          _playlistsSearchResult.isEmpty &&
                          _radioStationsSearchResult.isEmpty))
                  ? ValueListenableBuilder<List>(
                      valueListenable: searchHistoryNotifier,
                      builder: (context, searchHistory, _) {
                        final items = _suggestionsList.isEmpty
                            ? searchHistory
                            : _suggestionsList;

                        return Column(
                          key: const ValueKey('history'),
                          children: [
                            for (int index = 0; index < items.length; index++)
                              Builder(
                                builder: (context) {
                                  final query = items[index];
                                  final borderRadius = getItemBorderRadius(
                                    index,
                                    items.length,
                                  );

                                  return CustomBar(
                                    query,
                                    FluentIcons.search_24_regular,
                                    borderRadius: borderRadius,
                                    onTap: () async {
                                      await _submitSearch(query.toString());
                                    },
                                    onLongPress: () async {
                                      final confirm =
                                          await _showConfirmationDialog(
                                            context,
                                          ) ??
                                          false;
                                      if (confirm &&
                                          searchHistory.contains(query)) {
                                        final updatedHistory = List.from(
                                          searchHistory,
                                        )..remove(query);
                                        searchHistoryNotifier.value =
                                            updatedHistory;
                                        unawaited(
                                          addOrUpdateData<List>(
                                            'user',
                                            'searchHistory',
                                            updatedHistory,
                                          ),
                                        );
                                      }
                                    },
                                  );
                                },
                              ),
                          ],
                        );
                      },
                    )
                  : _buildSearchResults(context, primaryColor),
            ),
            const MiniPlayerBottomSpace(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context, Color primaryColor) {
    final widgets = <Widget>[];

    // Artists section: the library's first.
    final allArtists = [
      ..._libraryResult.artists,
      ..._artistsSearchResult.take(3),
    ];
    if (allArtists.isNotEmpty) {
      widgets.add(
        SectionTitle(
          context.l10n!.artists,
          primaryColor,
          icon: FluentIcons.person_24_filled,
        ),
      );

      final artists = allArtists;
      final libraryCount = _libraryResult.artists.length;
      for (var index = 0; index < artists.length; index++) {
        final artist = Map<String, dynamic>.from(artists[index]);
        final artistId =
            artist['ytid']?.toString() ?? artist['title']?.toString() ?? '';
        if (artistId.isEmpty) continue;

        final borderRadius = getItemBorderRadius(index, artists.length);
        // Library artists open as in the library, which also works offline.
        if (index < libraryCount) {
          widgets.add(
            PlaylistBar(
              key: listItemKey('search_library_artist', index, artist),
              artist['title'],
              playlistId: artist['ytid'],
              playlistArtwork: artist['image'],
              playlistData: artist,
              cubeIcon: FluentIcons.person_24_filled,
              borderRadius: borderRadius,
            ),
          );
          continue;
        }
        widgets.add(
          ArtistBar(
            key: listItemKey('search_artist', index, artist),
            artist: artist,
            borderRadius: borderRadius,
            onTap: () {
              context.push(
                '${NavigationManager.searchPath}/artist/${Uri.encodeComponent(artistId)}',
                extra: artist,
              );
            },
          ),
        );
      }
    }

    // Songs section
    if (_songsSearchResult.isNotEmpty) {
      widgets.add(
        SectionTitle(
          context.l10n!.songs,
          primaryColor,
          icon: FluentIcons.music_note_1_24_filled,
        ),
      );

      final songsCount = _songsSearchResult.length;
      for (var index = 0; index < songsCount; index++) {
        final song = _songsSearchResult[index];
        final borderRadius = getItemBorderRadius(index, songsCount);
        widgets.add(
          SongBar(
            song,
            true,
            key: listItemKey('search_song', index, song),
            showMusicDuration: true,
            borderRadius: borderRadius,
          ),
        );
      }
    }

    // Albums section
    if (_albumsSearchResult.isNotEmpty) {
      widgets.add(
        SectionTitle(
          context.l10n!.albums,
          primaryColor,
          icon: FluentIcons.album_24_filled,
        ),
      );

      final albumsCount = _albumsSearchResult.length;

      for (var index = 0; index < albumsCount; index++) {
        final playlist = _albumsSearchResult[index];
        final borderRadius = getItemBorderRadius(index, albumsCount);

        widgets.add(
          PlaylistBar(
            key: listItemKey('search_album', index, playlist),
            playlist['title'],
            playlistId: playlist['ytid'],
            playlistArtwork: playlist['image'],
            playlistData: _inLibrary(playlist) ? playlist : null,
            cubeIcon: FluentIcons.cd_16_filled,
            isAlbum: true,
            borderRadius: borderRadius,
          ),
        );
      }
    }

    // Playlists section
    if (_playlistsSearchResult.isNotEmpty) {
      widgets.add(
        SectionTitle(
          context.l10n!.playlists,
          primaryColor,
          icon: FluentIcons.text_bullet_list_24_filled,
        ),
      );

      final playlistsCount = _playlistsSearchResult.length;

      for (var index = 0; index < playlistsCount; index++) {
        final playlist = _playlistsSearchResult[index];
        final isLast = index == playlistsCount - 1;
        final borderRadius = getItemBorderRadius(index, playlistsCount);

        widgets.add(
          Padding(
            padding: isLast ? commonListViewBottomPadding : EdgeInsets.zero,
            child: PlaylistBar(
              key: listItemKey('search_playlist', index, playlist),
              playlist['title'],
              playlistId: playlist['ytid'],
              playlistArtwork: playlist['image'],
              playlistData: _inLibrary(playlist) ? playlist : null,
              cubeIcon: FluentIcons.apps_list_24_filled,
              borderRadius: borderRadius,
            ),
          ),
        );
      }
    }

    // Radio Stations section
    if (_radioStationsSearchResult.isNotEmpty) {
      widgets.add(
        SectionTitle(
          context.l10n!.radioStations,
          primaryColor,
          icon: FluentIcons.speaker_2_24_filled,
        ),
      );

      final stationsCount = _radioStationsSearchResult.length > maxSongsInList
          ? maxSongsInList
          : _radioStationsSearchResult.length;

      for (var index = 0; index < stationsCount; index++) {
        final station = _radioStationsSearchResult[index];
        final isLast = index == stationsCount - 1;

        widgets.add(
          Padding(
            padding: isLast ? commonListViewBottomPadding : EdgeInsets.zero,
            child: RadioStationCard(
              key: listItemKey('search_radio_station', index, station),
              station: station,
              onPressed: () async {
                final success = await audioHandler.playRadioStream(
                  id: station.id,
                  name: station.name,
                  streamUrl: station.streamUrl,
                  image: station.image,
                  genre: station.genre,
                );
                if (!success && context.mounted) {
                  showToast(context, context.l10n!.failedPlayingRadio);
                }
              },
            ),
          ),
        );
      }
    }

    return Column(key: const ValueKey('results'), children: widgets);
  }

  Future<bool?> _showConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return ConfirmationDialog(
          confirmationMessage: context.l10n!.removeSearchQueryQuestion,
          submitMessage: context.l10n!.confirm,
          onCancel: () {
            Navigator.of(context).pop(false);
          },
          onSubmit: () {
            Navigator.of(context).pop(true);
          },
        );
      },
    );
  }
}
