import 'package:youtube_explode_dart/youtube_explode_dart.dart';

typedef _JsonMap = Map<String, dynamic>;

/// A canonical YouTube Music artist result.
class MusicArtist {
  const MusicArtist({required this.id, required this.name, this.thumbnailUrl});

  /// Canonical `UC...` artist channel id.
  final String id;

  /// Display name returned by YouTube Music.
  final String name;

  /// Artist avatar URL, when YouTube Music exposes one.
  final String? thumbnailUrl;
}

/// Kind of a release listed on a YouTube Music artist page.
enum MusicReleaseType { album, single, ep, other }

/// A release (album, single or EP) as listed on a YouTube Music artist page.
class MusicAlbum {
  const MusicAlbum(
    this.id,
    this.title, {
    this.thumbnailUrl,
    this.type = MusicReleaseType.other,
    this.year,
  });

  /// Browse id of the release, e.g. `MPREb_...`.
  final String id;

  /// Display title of the release.
  final String title;

  /// Release artwork URL, when YouTube Music exposes one.
  final String? thumbnailUrl;

  /// Whether YouTube Music lists this release as a single or an EP. Album
  /// shelves only label their entries in the full grid, so an unlabelled
  /// release is [MusicReleaseType.other].
  final MusicReleaseType type;

  /// Release year, when YouTube Music exposes one.
  final String? year;

  @override
  String toString() => 'MusicAlbum($id, $title)';
}

/// A YouTube Music release page: the release itself plus its tracks.
class MusicReleasePage {
  const MusicReleasePage({
    required this.id,
    required this.title,
    this.artist,
    this.artistId,
    this.thumbnailUrl,
    this.year,
    this.tracks = const [],
  });

  /// Browse id of the release, e.g. `MPREb_...`.
  final String id;

  /// Display title of the release.
  final String title;

  /// Artist credited for the release, when YouTube Music exposes one.
  final String? artist;

  /// Channel id of that artist, when its name links to its page.
  final String? artistId;

  /// Release artwork URL, when YouTube Music exposes one.
  final String? thumbnailUrl;

  /// Release year, when YouTube Music exposes one.
  final String? year;

  /// The tracks of the release, in order.
  final List<Video> tracks;
}

/// A track of the artist page "Top songs" shelf.
class MusicTopSong {
  const MusicTopSong(this.video, this.playCount);

  /// The track itself.
  final Video video;

  /// Play count as displayed by YouTube Music, e.g. `1.2B plays`, when the
  /// shelf lists one.
  final String? playCount;
}

/// A YouTube Music artist page.
class MusicArtistProfile {
  const MusicArtistProfile({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    this.description,
    this.monthlyListeners,
    this.topSongs = const [],
    this.releases = const [],
    this.relatedArtists = const [],
  });

  /// Canonical `UC...` artist channel id, not necessarily the one the page was
  /// asked for: see [MusicClient.getArtistProfile].
  final String id;

  /// Display name returned by YouTube Music.
  final String name;

  /// Header artwork URL, when YouTube Music exposes one.
  final String? thumbnailUrl;

  /// Artist biography, when YouTube Music exposes one.
  final String? description;

  /// Monthly listeners as displayed by YouTube Music, e.g.
  /// `331M monthly audience`.
  final String? monthlyListeners;

  /// The tracks of the artist page "Top songs" shelf.
  final List<MusicTopSong> topSongs;

  /// Every release of the artist: albums, singles and EPs.
  final List<MusicAlbum> releases;

  /// Artists the "Fans might also like" shelf points to.
  final List<MusicArtist> relatedArtists;
}

/// How a YouTube Music track was uploaded.
enum MusicVideoType {
  /// The audio of a release (`MUSIC_VIDEO_TYPE_ATV`).
  song,

  /// An official music video (`MUSIC_VIDEO_TYPE_OMV`).
  officialVideo,

  /// Anything a user uploaded (`MUSIC_VIDEO_TYPE_UGC`): covers, fan edits,
  /// hour-long mixes, ambient sounds.
  userUpload,

  /// A podcast episode or a type this client doesn't know.
  other,
}

/// A track as YouTube Music lists it in a queue or a playlist.
class MusicTrack {
  const MusicTrack({
    required this.video,
    required this.type,
    this.artistId,
    this.album,
    this.thumbnailUrl,
  });

  /// The track's id, title, credited artists and duration. Only the fields
  /// YouTube Music lists in a row are known, the rest is left empty.
  final Video video;

  /// How the track was uploaded.
  final MusicVideoType type;

  /// Channel id of the first credited artist, when its name links to its
  /// page.
  final String? artistId;

  /// Album title, when YouTube Music lists one (songs only).
  final String? album;

  /// Largest artwork URL YouTube Music lists for the track.
  final String? thumbnailUrl;

  @override
  String toString() => 'MusicTrack(${video.id}, ${video.title})';
}

/// A playlist as listed on a YouTube Music shelf.
class MusicPlaylistSummary {
  const MusicPlaylistSummary({
    required this.id,
    required this.title,
    this.thumbnailUrl,
    this.shelf,
  });

  /// Playlist id, without the `VL` browse prefix.
  final String id;

  /// Display title of the playlist.
  final String title;

  /// Playlist artwork URL, when YouTube Music exposes one.
  final String? thumbnailUrl;

  /// Title of the shelf the playlist sits on, e.g. `Chill pop`.
  final String? shelf;

  @override
  String toString() => 'MusicPlaylistSummary($id, $title)';
}

/// An entry of YouTube Music's "Moods & genres" page.
class MusicMood {
  const MusicMood({
    required this.title,
    required this.params,
    required this.isGenre,
  });

  /// Display title, e.g. `Feel good` or `Jazz`.
  final String title;

  /// Browse params for [MusicClient.getMoodPlaylists]. They expire: read
  /// them again from [MusicClient.getMoods] instead of storing them for
  /// long.
  final String params;

  /// Whether the entry is a genre rather than a mood or moment.
  final bool isGenre;

  @override
  String toString() => 'MusicMood($title)';
}

/// Queries the YouTube Music (`WEB_REMIX`) browse endpoints.
class MusicClient {
  /// Initializes an instance of [MusicClient].
  const MusicClient(this._httpClient);

  final YoutubeHttpClient _httpClient;

  static const _remixContext = {
    'client': {
      'clientName': 'WEB_REMIX',
      'clientVersion': '1.20240101.01.00',
      'hl': 'en',
    },
  };

  /// Search filter that restricts results to artists only.
  static const _artistsSearchParams = 'EgWKAQIgAWoMEA4QChADEAQQCRAF';

  /// Search filter for the dedicated "Songs" shelf.
  static const _songsSearchParams = 'EgWKAQIIAWoMEA4QChADEAQQCRAF';

  static const _artistPageType = 'MUSIC_PAGE_TYPE_ARTIST';

  /// Stands in for the channel of a track whose artist page is unknown.
  static const _unknownChannelId = 'UC0000000000000000000000';

  /// Matches the play count of a top song, e.g. `1.2B plays`. The client asks
  /// for `hl: en`, so the wording is stable.
  static final _playCountPattern = RegExp(
    r'^[\d.,]+\s?[KMB]?\s+plays$',
    caseSensitive: false,
  );

  /// Searches YouTube Music for canonical artist entries matching [query].
  Future<List<MusicArtist>> searchArtists(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return [];

    final root = await _httpClient.sendPost('search', {
      'context': _remixContext,
      'query': normalizedQuery,
      'params': _artistsSearchParams,
    });

    final results = <MusicArtist>[];
    final seen = <String>{};
    for (final item in _findRenderers(
      root,
      'musicResponsiveListItemRenderer',
    )) {
      final endpoint = item
          .getMap('navigationEndpoint')
          ?.getMap('browseEndpoint');
      final id = endpoint?.getValue<String>('browseId');
      if (id == null || !id.startsWith('UC') || !seen.add(id)) continue;

      final pageType = endpoint
          ?.getMap('browseEndpointContextSupportedConfigs')
          ?.getMap('browseEndpointContextMusicConfig')
          ?.getValue<String>('pageType');
      if (pageType != _artistPageType) continue;

      final name = _flexColumnText(item, 0) ?? '';
      if (name.trim().isEmpty) continue;

      results.add(
        MusicArtist(
          id: id,
          name: name.trim(),
          thumbnailUrl: _thumbnailUrl(item, 'thumbnail'),
        ),
      );
    }
    return results;
  }

  /// Searches the YouTube Music "Songs" shelf for [query].
  ///
  /// When supplied, [expectedArtist] and [expectedTitle] must loosely match
  /// the result's credited artist and title. This prevents common-title
  /// searches from returning the wrong recording.
  Future<Video?> searchSong(
    String query, {
    String? expectedArtist,
    String? expectedTitle,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return null;

    final root = await _httpClient.sendPost('search', {
      'context': _remixContext,
      'query': normalizedQuery,
      'params': _songsSearchParams,
    }, validate: true);

    final isValidating = expectedArtist != null || expectedTitle != null;
    Video? fallback;
    for (final item in _findRenderers(
      root,
      'musicResponsiveListItemRenderer',
    )) {
      final videoId = _trackVideoId(item);
      if (videoId == null) continue;

      final title = _flexColumnText(item, 0);
      if (title == null || title.isEmpty) continue;

      final subtitleParts = _splitBullets(_flexColumnText(item, 1));
      final artist = subtitleParts.isNotEmpty ? subtitleParts.first : '';

      final video = _trackVideo(item, videoId, title, artist, null);
      fallback ??= video;

      if (expectedArtist != null && !_looselyMatch(artist, expectedArtist)) {
        continue;
      }
      if (expectedTitle != null && !_looselyMatch(title, expectedTitle)) {
        continue;
      }

      return video;
    }

    // Only use the first result when no expected values were provided.
    return isValidating ? null : fallback;
  }

  /// Splits a `Song • Artist • Album` style subtitle line on its bullet
  /// separators.
  List<String> _splitBullets(String? text) {
    if (text == null) return const [];
    return text
        .split('•')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  /// Compares normalized word sets, allowing word-order and credit changes.
  bool _looselyMatch(String candidate, String expected) {
    final a = _wordsForMatch(candidate);
    final b = _wordsForMatch(expected);
    if (a.isEmpty || b.isEmpty) return true;
    final shorter = a.length <= b.length ? a : b;
    final longer = identical(shorter, a) ? b : a;
    return shorter.every(longer.contains);
  }

  Set<String> _wordsForMatch(String input) =>
      _foldDiacritics(input.toLowerCase())
          // Keep Unicode letters and numbers so non-Latin titles remain
          // matchable.
          .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .toSet();

  /// Folds common Latin accents to improve matching across spellings.
  String _foldDiacritics(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_diacriticFold[char] ?? char);
    }
    return buffer.toString();
  }

  static const _diacriticFold = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'å': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'ç': 'c',
    'ñ': 'n',
  };

  /// Returns a YouTube Music artist page: header details, top songs, the full
  /// discography and the artists it points to.
  ///
  /// [channelId] does not have to be the channel of the artist itself: the
  /// channel that uploads its videos — a label, a VEVO channel — answers with
  /// a partial page of the same artist, whose header still points at the
  /// canonical channel. [MusicArtistProfile.id] holds that one, so a caller
  /// that asked with an uploader can tell and read the real page instead.
  Future<MusicArtistProfile> getArtistProfile(dynamic channelId) async {
    final id = ChannelId.fromString(channelId).value;
    final root = await _browse(id);

    final header =
        _firstRenderer(root, 'musicImmersiveHeaderRenderer') ??
        _firstRenderer(root, 'musicVisualHeaderRenderer');
    final name = (_runsText(header?.getMap('title')) ?? '').trim();
    final canonicalId = _headerChannelId(header) ?? id;

    return MusicArtistProfile(
      id: canonicalId,
      name: name,
      thumbnailUrl: _thumbnailUrl(header, 'thumbnail'),
      description: _runsText(header?.getMap('description')),
      monthlyListeners: _runsText(header?.getMap('monthlyListenerCount')),
      topSongs: _parseTopSongs(root, channelId: canonicalId, author: name),
      releases: await _collectDiscography(root),
      relatedArtists: _collectRelatedArtists(
        root,
      ).where((artist) => artist.id != canonicalId).toList(),
    );
  }

  /// Channel the subscribe button of a page header subscribes to, which is the
  /// artist itself even on the page of a channel that only uploads for it.
  String? _headerChannelId(_JsonMap? header) {
    final channelId = header
        ?.getMap('subscriptionButton')
        ?.getMap('subscribeButtonRenderer')
        ?.getValue<String>('channelId');
    return (channelId != null && channelId.startsWith('UC')) ? channelId : null;
  }

  /// Returns a release with its tracks, credited to the artist its own header
  /// names.
  Future<MusicReleasePage> getAlbum(String albumBrowseId) async {
    final root = await _browse(albumBrowseId);
    final header =
        _firstRenderer(root, 'musicResponsiveHeaderRenderer') ??
        _firstRenderer(root, 'musicDetailHeaderRenderer');
    final albumArtist = _runsText(header?.getMap('straplineTextOne'))?.trim();
    final albumArtistId = _straplineChannelId(header);

    final videos = <Video>[];
    final seen = <String>{};
    for (final item in _findRenderers(
      root,
      'musicResponsiveListItemRenderer',
    )) {
      final videoId = _trackVideoId(item);
      if (videoId == null || !seen.add(videoId)) continue;

      final title = _flexColumnText(item, 0);
      if (title == null || title.isEmpty) continue;

      videos.add(
        _trackVideo(item, videoId, title, albumArtist ?? '', albumArtistId),
      );
    }

    return MusicReleasePage(
      id: albumBrowseId,
      title: _runsText(header?.getMap('title'))?.trim() ?? '',
      artist: albumArtist,
      artistId: albumArtistId,
      thumbnailUrl: _thumbnailUrl(header, 'thumbnail'),
      year: _releaseYearOf(_subtitleParts(header)),
      tracks: videos,
    );
  }

  /// Channel id behind the artist name of a release header, when it links to
  /// the page of that artist.
  String? _straplineChannelId(_JsonMap? header) {
    final runs = header?.getMap('straplineTextOne')?.getList('runs');
    for (final run in runs?.whereType<Map>() ?? const <Map>[]) {
      final browseId = run
          .cast<String, dynamic>()
          .getMap('navigationEndpoint')
          ?.getMap('browseEndpoint')
          ?.getValue<String>('browseId');
      if (browseId != null && browseId.startsWith('UC')) return browseId;
    }
    return null;
  }

  /// The radio YouTube Music plays after [videoId]: about 50 tracks like it,
  /// starting with the track itself. A song seeds a radio of songs, an
  /// official video one of official videos. [country] (ISO 3166-1 alpha-2)
  /// biases the picks towards a region.
  Future<List<MusicTrack>> getRadio(String videoId, {String? country}) async {
    final id = VideoId(videoId).value;
    final root = await _httpClient.sendPost('next', {
      'context': _contextFor(country),
      'videoId': id,
      'playlistId': 'RDAMVM$id',
      'isAudioOnly': true,
      'enablePersistentPlaylistPanel': true,
    });

    final tracks = <MusicTrack>[];
    final seen = <String>{};
    for (final item in _findRenderers(root, 'playlistPanelVideoRenderer')) {
      final trackId = item.getValue<String>('videoId');
      if (trackId == null || !seen.add(trackId)) continue;
      final title = _runsText(item.getMap('title'))?.trim();
      if (title == null || title.isEmpty) continue;

      // `Artist • Album • 2019` for songs, `Artist • 1.2B views • …` for
      // videos.
      final byline = item.getMap('longBylineText');
      final parts = _splitBullets(_runsText(byline));
      final type = _videoTypeOf(item);
      final thumbnails = item.getMap('thumbnail')?.getList('thumbnails');
      final thumbnail = thumbnails == null || thumbnails.isEmpty
          ? null
          : thumbnails.last;
      tracks.add(
        MusicTrack(
          video: _trackVideoFrom(
            trackId,
            title,
            parts.isEmpty ? '' : parts.first,
            _parseDuration(_runsText(item.getMap('lengthText'))),
          ),
          type: type,
          artistId: _artistIdIn(byline),
          album: type == MusicVideoType.song && parts.length > 1
              ? parts[1]
              : null,
          thumbnailUrl: thumbnail is Map
              ? thumbnail.cast<String, dynamic>().getValue<String>('url')
              : null,
        ),
      );
    }
    return tracks;
  }

  /// The tracks of a playlist: its first page, which holds the first 100
  /// tracks or so. [playlistId] may carry the `VL` browse prefix.
  Future<List<MusicTrack>> getPlaylistTracks(
    String playlistId, {
    String? country,
  }) async {
    final browseId = playlistId.startsWith('VL') ? playlistId : 'VL$playlistId';
    final root = await _httpClient.sendPost('browse', {
      'context': _contextFor(country),
      'browseId': browseId,
    });

    final tracks = <MusicTrack>[];
    final seen = <String>{};
    for (final item in _findRenderers(
      root,
      'musicResponsiveListItemRenderer',
    )) {
      final trackId =
          item.getMap('playlistItemData')?.getValue<String>('videoId') ??
          _trackVideoId(item);
      if (trackId == null || !seen.add(trackId)) continue;
      final title = _flexColumnText(item, 0)?.trim();
      if (title == null || title.isEmpty) continue;

      final artistColumn = _flexColumn(item, 1);
      final albumColumn = _flexColumn(item, 2);
      tracks.add(
        MusicTrack(
          video: _trackVideoFrom(
            trackId,
            title,
            _runsText(artistColumn) ?? '',
            _parseDuration(_fixedColumnText(item)),
          ),
          type: _videoTypeOf(item),
          artistId: _artistIdIn(artistColumn),
          album: _runsText(albumColumn),
          thumbnailUrl: _thumbnailUrl(item, 'thumbnail'),
        ),
      );
    }
    return tracks;
  }

  /// The chart playlists of YouTube Music's Charts page for [country]
  /// (ISO 3166-1 alpha-2, `ZZ` for global), e.g. `Top 100 Music Videos
  /// Global`. Without signing in YouTube Music lists video charts only.
  Future<List<MusicPlaylistSummary>> getCharts({String country = 'ZZ'}) async {
    final root = await _httpClient.sendPost('browse', {
      'context': _remixContext,
      'browseId': 'FEmusic_charts',
      'formData': {
        'selectedValues': [country],
      },
    });
    return _collectPlaylists(root);
  }

  /// YouTube Music's moods and moments (`Chill`, `Feel good`, `Workout`…)
  /// and genres, in its own order. [country] decides the regional genres
  /// listed.
  Future<List<MusicMood>> getMoods({String? country}) async {
    final root = await _httpClient.sendPost('browse', {
      'context': _contextFor(country),
      'browseId': 'FEmusic_moods_and_genres',
    });

    final moods = <MusicMood>[];
    var grid = 0;
    for (final section in _findRenderers(root, 'gridRenderer')) {
      final items = section.getList('items') ?? const [];
      for (final item in items.whereType<Map>()) {
        final button = item.cast<String, dynamic>().getMap(
          'musicNavigationButtonRenderer',
        );
        final title = _runsText(button?.getMap('buttonText'))?.trim();
        final params = button
            ?.getMap('clickCommand')
            ?.getMap('browseEndpoint')
            ?.getValue<String>('params');
        if (title == null || title.isEmpty || params == null) continue;
        // The page lists moods and moments first, genres second.
        moods.add(MusicMood(title: title, params: params, isGenre: grid > 0));
      }
      grid++;
    }
    return moods;
  }

  /// The playlists YouTube Music curates for a mood or genre, by shelf.
  /// [params] comes from a current [getMoods] answer.
  Future<List<MusicPlaylistSummary>> getMoodPlaylists(
    String params, {
    String? country,
  }) async {
    final root = await _httpClient.sendPost('browse', {
      'context': _contextFor(country),
      'browseId': 'FEmusic_moods_and_genres_category',
      'params': params,
    });
    return _collectPlaylists(root);
  }

  Map<String, dynamic> _contextFor(String? country) => country == null
      ? _remixContext
      : {
          'client': {
            ...(_remixContext['client']! as Map<String, dynamic>),
            'gl': country,
          },
        };

  /// Every playlist of the shelves under [root], with its shelf's title.
  List<MusicPlaylistSummary> _collectPlaylists(_JsonMap root) {
    final playlists = <String, MusicPlaylistSummary>{};
    void collect(dynamic node, String? shelf) {
      for (final item in _findRenderers(node, 'musicTwoRowItemRenderer')) {
        final browseId = item
            .getMap('navigationEndpoint')
            ?.getMap('browseEndpoint')
            ?.getValue<String>('browseId');
        if (browseId == null || !browseId.startsWith('VL')) continue;
        final title = _runsText(item.getMap('title'))?.trim();
        if (title == null || title.isEmpty) continue;
        final id = browseId.substring(2);
        playlists.putIfAbsent(
          id,
          () => MusicPlaylistSummary(
            id: id,
            title: title,
            thumbnailUrl: _thumbnailUrl(item, 'thumbnailRenderer'),
            shelf: shelf,
          ),
        );
      }
    }

    for (final shelf in [
      ..._findRenderers(root, 'musicCarouselShelfRenderer'),
      ..._findRenderers(root, 'gridRenderer'),
    ]) {
      final header =
          shelf
              .getMap('header')
              ?.getMap('musicCarouselShelfBasicHeaderRenderer')
              ?.getMap('title') ??
          shelf.getMap('header')?.getMap('gridHeaderRenderer')?.getMap('title');
      collect(shelf, _runsText(header)?.trim());
    }
    return playlists.values.toList();
  }

  MusicVideoType _videoTypeOf(_JsonMap item) {
    for (final config in _findRenderers(item, 'watchEndpointMusicConfig')) {
      switch (config.getValue<String>('musicVideoType')) {
        case 'MUSIC_VIDEO_TYPE_ATV':
          return MusicVideoType.song;
        case 'MUSIC_VIDEO_TYPE_OMV':
          return MusicVideoType.officialVideo;
        case 'MUSIC_VIDEO_TYPE_UGC':
          return MusicVideoType.userUpload;
      }
    }
    return MusicVideoType.other;
  }

  /// The channel id of the first artist linked in a text's runs.
  String? _artistIdIn(_JsonMap? text) {
    for (final run in text?.getList('runs') ?? const []) {
      if (run is! Map) continue;
      final browseId = run
          .cast<String, dynamic>()
          .getMap('navigationEndpoint')
          ?.getMap('browseEndpoint')
          ?.getValue<String>('browseId');
      if (browseId != null && browseId.startsWith('UC')) return browseId;
    }
    return null;
  }

  _JsonMap? _flexColumn(_JsonMap item, int index) {
    final columns = item.getList('flexColumns');
    if (columns == null || columns.length <= index) return null;
    final column = columns[index];
    if (column is! Map) return null;
    return column
        .cast<String, dynamic>()
        .getMap('musicResponsiveListItemFlexColumnRenderer')
        ?.getMap('text');
  }

  Future<_JsonMap> _browse(String browseId, {String? params}) {
    return _httpClient.sendPost('browse', {
      'context': _remixContext,
      'browseId': browseId,
      if (params != null) 'params': params,
    });
  }

  /// Every release of the artist page: the grid behind each shelf's "More"
  /// button, plus the entries only shown inline.
  Future<List<MusicAlbum>> _collectDiscography(_JsonMap root) async {
    final grids = await Future.wait([
      for (final more in _collectMoreReleaseBrowses(root))
        _browse(
          more.$1,
          params: more.$2,
        ).catchError((_) => <String, dynamic>{}),
    ]);

    // Grids first: they label the release type, the inline previews of an
    // album shelf do not, and [_collectReleases] keeps the first entry seen.
    final releases = <String, MusicAlbum>{};
    for (final grid in grids) {
      _collectReleases(grid, releases);
    }
    _collectReleases(root, releases);
    return releases.values.toList();
  }

  List<MusicTopSong> _parseTopSongs(
    _JsonMap root, {
    required String channelId,
    required String author,
  }) {
    final shelf = _firstRenderer(root, 'musicShelfRenderer');
    if (shelf == null) return const [];

    final songs = <MusicTopSong>[];
    final seen = <String>{};
    for (final item in _findRenderers(
      shelf,
      'musicResponsiveListItemRenderer',
    )) {
      final videoId = _trackVideoId(item);
      if (videoId == null || !seen.add(videoId)) continue;

      final title = _flexColumnText(item, 0);
      if (title == null || title.isEmpty) continue;

      final trackAuthor = _flexColumnText(item, 1);
      songs.add(
        MusicTopSong(
          _trackVideo(
            item,
            videoId,
            title,
            (trackAuthor == null || trackAuthor.isEmpty) ? author : trackAuthor,
            channelId,
          ),
          _playCountText(item),
        ),
      );
    }

    return songs;
  }

  /// One track row of a shelf or of a release, as a [Video]. Only the fields
  /// YouTube Music lists in a row are known, the rest is left empty.
  Video _trackVideo(
    _JsonMap item,
    String videoId,
    String title,
    String author,
    String? channelId,
  ) => _trackVideoFrom(
    videoId,
    title,
    author,
    _parseDuration(_fixedColumnText(item)),
    channelId,
  );

  Video _trackVideoFrom(
    String videoId,
    String title,
    String author,
    Duration? duration, [
    String? channelId,
  ]) {
    return Video(
      VideoId(videoId),
      title,
      author,
      ChannelId.fromString(channelId ?? _unknownChannelId),
      null,
      null,
      null,
      '',
      duration,
      ThumbnailSet(videoId),
      null,
      const Engagement(0, null, null),
      false,
    );
  }

  /// The play count column of a top song, when the shelf lists one. Its
  /// position varies, so every column after the title is probed.
  String? _playCountText(_JsonMap item) {
    for (var index = 1; index < 4; index++) {
      final text = _flexColumnText(item, index);
      if (text != null && _playCountPattern.hasMatch(text)) return text;
    }
    return null;
  }

  void _collectReleases(dynamic root, Map<String, MusicAlbum> into) {
    for (final item in _findRenderers(root, 'musicTwoRowItemRenderer')) {
      final browseId = item
          .getMap('navigationEndpoint')
          ?.getMap('browseEndpoint')
          ?.getValue<String>('browseId');
      if (browseId == null || !browseId.startsWith('MPRE')) continue;

      final title = _runsText(item.getMap('title'));
      // `Album • 2019`, `Single • 2021`, or just the year when the entry is an
      // inline preview.
      final subtitle = _subtitleParts(item);
      into.putIfAbsent(
        browseId,
        () => MusicAlbum(
          browseId,
          title?.trim() ?? '',
          thumbnailUrl: _thumbnailUrl(item, 'thumbnailRenderer'),
          type: _releaseTypeOf(subtitle),
          year: _releaseYearOf(subtitle),
        ),
      );
    }
  }

  /// Collects the artists of the "Fans might also like" shelf. They sit in the
  /// same rows as the releases, told apart by their channel browse id.
  List<MusicArtist> _collectRelatedArtists(dynamic root) {
    final artists = <String, MusicArtist>{};
    for (final item in _findRenderers(root, 'musicTwoRowItemRenderer')) {
      final endpoint = item
          .getMap('navigationEndpoint')
          ?.getMap('browseEndpoint');
      final browseId = endpoint?.getValue<String>('browseId');
      if (browseId == null || !browseId.startsWith('UC')) continue;

      final pageType = endpoint
          ?.getMap('browseEndpointContextSupportedConfigs')
          ?.getMap('browseEndpointContextMusicConfig')
          ?.getValue<String>('pageType');
      if (pageType != _artistPageType) continue;

      final name = _runsText(item.getMap('title'))?.trim();
      if (name == null || name.isEmpty) continue;

      artists.putIfAbsent(
        browseId,
        () => MusicArtist(
          id: browseId,
          name: name,
          thumbnailUrl: _thumbnailUrl(item, 'thumbnailRenderer'),
        ),
      );
    }
    return artists.values.toList();
  }

  List<(String, String?)> _collectMoreReleaseBrowses(_JsonMap root) {
    final result = <(String, String?)>[];
    for (final header in _findRenderers(
      root,
      'musicCarouselShelfBasicHeaderRenderer',
    )) {
      final endpoint = header
          .getMap('moreContentButton')
          ?.getMap('buttonRenderer')
          ?.getMap('navigationEndpoint')
          ?.getMap('browseEndpoint');
      final browseId = endpoint?.getValue<String>('browseId');
      if (browseId == null || !browseId.startsWith('MPAD')) continue;
      result.add((browseId, endpoint?.getValue<String>('params')));
    }
    return result;
  }

  List<String> _subtitleParts(_JsonMap? item) {
    final subtitle = _runsText(item?.getMap('subtitle'));
    if (subtitle == null) return const [];
    return subtitle
        .split('•')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  MusicReleaseType _releaseTypeOf(List<String> subtitleParts) {
    for (final part in subtitleParts) {
      switch (part.toLowerCase()) {
        case 'album':
          return MusicReleaseType.album;
        case 'single':
          return MusicReleaseType.single;
        case 'ep':
          return MusicReleaseType.ep;
      }
    }
    return MusicReleaseType.other;
  }

  String? _releaseYearOf(List<String> subtitleParts) {
    for (final part in subtitleParts) {
      if (RegExp(r'^(19|20)\d{2}$').hasMatch(part)) return part;
    }
    return null;
  }

  String? _trackVideoId(_JsonMap item) {
    return item
        .getMap('overlay')
        ?.getMap('musicItemThumbnailOverlayRenderer')
        ?.getMap('content')
        ?.getMap('musicPlayButtonRenderer')
        ?.getMap('playNavigationEndpoint')
        ?.getMap('watchEndpoint')
        ?.getValue<String>('videoId');
  }

  String? _flexColumnText(_JsonMap item, int index) =>
      _runsText(_flexColumn(item, index));

  String? _runsText(_JsonMap? node) {
    final runs = node?.getList('runs')?.whereType<Map>().parseRuns();
    return (runs == null || runs.isEmpty) ? null : runs;
  }

  String? _fixedColumnText(_JsonMap item) {
    final columns = item.getList('fixedColumns');
    if (columns == null || columns.isEmpty) return null;
    final lastColumn = columns.last;
    if (lastColumn is! Map) return null;
    return lastColumn
        .cast<String, dynamic>()
        .getMap('musicResponsiveListItemFixedColumnRenderer')
        ?.getMap('text')
        ?.getList('runs')
        ?.whereType<Map>()
        .parseRuns();
  }

  /// The largest artwork URL under [key], which holds a thumbnail renderer:
  /// `thumbnail` on headers and list items, `thumbnailRenderer` on shelf rows.
  String? _thumbnailUrl(_JsonMap? node, String key) {
    final thumbnails = node
        ?.getMap(key)
        ?.getMap('musicThumbnailRenderer')
        ?.getMap('thumbnail')
        ?.getList('thumbnails');
    if (thumbnails == null || thumbnails.isEmpty) return null;
    final thumbnail = thumbnails.last;
    if (thumbnail is! Map) return null;
    return thumbnail.cast<String, dynamic>().getValue<String>('url');
  }

  Duration? _parseDuration(String? value) {
    if (value == null) return null;
    final parts = value.trim().split(':');
    if (parts.isEmpty || parts.length > 3) return null;

    var seconds = 0;
    for (final part in parts) {
      final n = int.tryParse(part.trim());
      if (n == null) return null;
      seconds = seconds * 60 + n;
    }
    return Duration(seconds: seconds);
  }

  _JsonMap? _firstRenderer(dynamic node, String rendererKey) {
    for (final renderer in _findRenderers(node, rendererKey)) {
      return renderer;
    }
    return null;
  }

  Iterable<_JsonMap> _findRenderers(dynamic node, String rendererKey) sync* {
    if (node is Map) {
      final match = node[rendererKey];
      if (match is Map) yield match.cast<String, dynamic>();
      for (final value in node.values) {
        yield* _findRenderers(value, rendererKey);
      }
    } else if (node is List) {
      for (final value in node) {
        yield* _findRenderers(value, rendererKey);
      }
    }
  }
}

extension _MapReader on Map<String, dynamic> {
  Map<String, dynamic>? getMap(String key) {
    final value = this[key];
    return value is Map ? value.cast<String, dynamic>() : null;
  }

  List<dynamic>? getList(String key) {
    final value = this[key];
    return value is List ? value : null;
  }

  T? getValue<T>(String key) {
    final value = this[key];
    return value is T ? value : null;
  }
}

extension _RunsParser on Iterable<Map<dynamic, dynamic>> {
  String parseRuns() {
    return map((run) => run['text']?.toString() ?? '').join();
  }
}
