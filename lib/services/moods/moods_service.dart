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
import 'dart:io';
import 'dart:math';

import 'package:hive/hive.dart';
import 'package:intl/intl.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler, logger;
import 'package:musify/services/common_services.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/moods/mix_engine.dart';
import 'package:musify/services/moods/moods_preferences.dart';
import 'package:musify/services/moods/moods_worker.dart';
import 'package:musify/services/moods/taste.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/formatter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart'
    show YoutubeHttpClient;
import 'package:youtube_music_explode_dart/youtube_music_explode_dart.dart';

/// The buttons of the Moods row: the Mix, then YouTube Music's moods and
/// moments, by their English title there.
enum Mood {
  mix(null),
  feelGood('Feel good'),
  chill('Chill'),
  energize('Energize'),
  focus('Focus'),
  party('Party'),
  romance('Romance'),
  sad('Sad'),
  workout('Workout'),
  commute('Commute'),
  sleep('Sleep');

  const Mood(this.youtubeTitle);
  final String? youtubeTitle;
}

/// A YouTube Music genre the user listens to, with the artists that say so.
typedef DetectedGenre = ({
  String title,
  String label,
  double score,
  List<String> artists,
});

/// Builds the Moods' queues and Zenify's own playlists from the user's taste
/// (see [Taste]) and YouTube Music: the radio of the user's songs, the
/// playlists it curates for each mood and genre, and its charts.
///
/// What comes from the network is cached in the `cache` box, which backups
/// leave out; the user's tuning and saved playlists live in the library (see
/// `moods_preferences.dart`).
class MoodsService {
  MoodsService() {
    offlineMode.addListener(_onAvailabilityChanged);
    moodsEnabled.addListener(_onAvailabilityChanged);
  }

  final _worker = MoodsWorker();
  int _generation = 0;

  bool get _online => !offlineMode.value;
  bool get _enabled => _online && moodsEnabled.value;

  void _onAvailabilityChanged() {
    if (!_enabled) _cancelPending();
  }

  void _cancelPending() {
    _generation++;
    _worker.cancel();
    _radios.clear();
    _catalog = null;
    _readingGenres = null;
    _tasteMemo = null;
  }

  /// Releases listeners on a short-lived service (the app shares one).
  void dispose() {
    offlineMode.removeListener(_onAvailabilityChanged);
    moodsEnabled.removeListener(_onAvailabilityChanged);
    _cancelPending();
  }

  Future<T> _run<T>(_Task<T> task) {
    if (!_online) return Future.error(const MoodsCancelled());
    return _worker.run(_musicTask(task));
  }

  /// What the cached playlists were made with. Blocked artists and left-out
  /// genres are filtered when a playlist is read, so only the discovery
  /// asks for a new one.
  String get _tuningSignature => moodsTuning.value.discovery.name;
  Box get _cache => Hive.box('cache');

  /// The device's region, for regional moods, genres and charts.
  String? get country {
    final parts = Platform.localeName.split(RegExp('[_.-]'));
    return parts.length > 1 && parts[1].length == 2
        ? parts[1].toUpperCase()
        : null;
  }

  AppLocalizations get _l10n => lookupAppLocalizations(languageSetting);

  final _radios = <String, Future<List<Map>>>{};

  /// The user's taste right now, from the library. The tuning page asks for
  /// it [withBlocked] artists too, to list them under their names.
  Taste taste({bool withBlocked = false}) {
    // Making the day's playlists asks for it a dozen times in a row.
    final now = DateTime.now();
    final memo = _tasteMemo;
    if (memo != null &&
        memo.withBlocked == withBlocked &&
        memo.tuning == moodsTuning.value &&
        memo.library == _libraryIdentity &&
        now.difference(memo.at) < const Duration(seconds: 30)) {
      return memo.taste;
    }
    final taste = _readTaste(withBlocked);
    _tasteMemo = (
      taste: taste,
      at: now,
      withBlocked: withBlocked,
      tuning: moodsTuning.value,
      library: _libraryIdentity,
    );
    return taste;
  }

  ({
    Taste taste,
    DateTime at,
    bool withBlocked,
    MoodsTuning tuning,
    Object library,
  })?
  _tasteMemo;

  // Notifier lists are replaced when the library is edited or restored.
  // Comparing their identities keeps the memo cheap without delaying edits.
  Object get _libraryIdentity => (
    userCustomPlaylists.value,
    userPlaylistFolders.value,
    userOfflineSongs.value,
    userRecentlyPlayed.value,
    userLikedSongsList.value,
    userLikedPlaylists.value,
  );

  Taste _readTaste(bool withBlocked) {
    final kept = <Map>[
      for (final playlist in [
        ...userCustomPlaylists.value,
        for (final folder in userPlaylistFolders.value)
          ...(folder['playlists'] as List? ?? const []).whereType<Map>(),
      ])
        ...(playlist['list'] as List? ?? const []).whereType<Map>(),
      ...userOfflineSongs.value.whereType<Map>(),
    ];
    return Taste.of(
      recap: _recapMonths(),
      recentlyPlayed: userRecentlyPlayed.value,
      liked: userLikedSongsList.value,
      kept: kept,
      likedArtists: [
        for (final artist in getLikedArtistItems())
          artist['title']?.toString() ?? '',
      ],
      blockedArtists: withBlocked ? const {} : moodsTuning.value.blockedArtists,
      notSongs: _notSongs,
    );
  }

  /// Library songs YouTube Music says are no songs: uploads by users, such
  /// as rain for sleeping or an hour-long mix. Learnt from the radios, which
  /// start with the song they come from, and kept in the cache.
  late final Set<String> _notSongs = {
    for (final id in _cache.get(_notSongsKey) as List? ?? const [])
      id.toString(),
  };
  static const _notSongsKey = 'moods:notSongs';

  bool _isSong(Object? song) =>
      song is Map && !_notSongs.contains(song['ytid']?.toString());

  /// The songs of each recap month, the current one first.
  List<Map> _recapMonths() {
    final keys = listeningStatsService.availableMonthKeys.toList()
      ..sort((a, b) => b.compareTo(a));
    return [
      for (final key in keys)
        if (listeningStatsService.monthStats(key)?['songs'] case final Map s) s,
    ];
  }

  /// What YouTube Music plays after [id], songs only. Nothing when YouTube
  /// Music says [id] itself is no song: its radio would be more of it.
  Future<List<Map>> radio(String id) {
    if (!_online) return Future.value(const []);
    final generation = _generation;
    if (_radios.length > 200) _radios.clear();
    final region = country;
    return _radios[id] ??= _run(_radioTask(id, region))
        .then((radio) {
          if (generation != _generation || !_online) return <Map>[];
          if (radio.seedIsSong) return radio.songs;
          if (_notSongs.add(id)) {
            unawaited(_cache.put(_notSongsKey, _notSongs.toList()));
          }
          return <Map>[];
        })
        .catchError((Object error) {
          if (error is MoodsCancelled) return <Map>[];
          _radios.remove(id);
          logger.log('Moods radio failed for $id', error: error);
          return <Map>[];
        });
  }

  /// The Mix: the user's recent taste, with discovery.
  Future<List<Map>> mix({
    Discovery? discovery,
    int length = 40,
    Random? random,
  }) async {
    if (!_enabled) return const [];
    final generation = _generation;
    final shuffle = random ?? Random();
    final taste = this.taste();
    var seeds = _pickSeeds(taste, shuffle);
    if (seeds.isEmpty) {
      // A new install: start from what is popular here, and learn.
      final top = await _chartSongs();
      seeds = {for (final song in top.take(6)) song['ytid'].toString(): 0.5};
    }
    if (generation != _generation || !_enabled) return const [];
    final radios = await _radiosOf(seeds.keys);
    if (generation != _generation || !_enabled) return const [];
    final excluded = await _excludedArtists();
    return assembleQueue(
      taste: taste,
      scored: scoreRadios(taste: taste, radios: radios, seedWeights: seeds),
      discovery: discovery ?? moodsTuning.value.discovery,
      length: length,
      excludedArtists: excluded,
      random: shuffle,
    );
  }

  /// A mood's queue: songs of YouTube Music's playlists for it, ordered by
  /// the user's taste (see [_fromPool]).
  Future<List<Map>> mood(Mood mood, {int length = 40, Random? random}) async {
    if (!_enabled) return const [];
    final generation = _generation;
    if (mood == Mood.mix) return mix(length: length, random: random);
    final pool = await _moodPool(mood);
    if (pool.isEmpty || generation != _generation || !_enabled) return const [];
    return _fromPool(pool, length: length, random: random ?? Random());
  }

  /// Only songs of [pool] make it, so the vibe holds: a song listed by more
  /// of the mood's playlists is more central to it, an artist the user
  /// listens to ranks higher, and so does a song YouTube Music plays after
  /// the user's own songs of the mood.
  Future<List<Map>> _fromPool(
    List<Map> pool, {
    required int length,
    required Random random,
    Discovery? discovery,
  }) async {
    if (!_enabled) return const [];
    final generation = _generation;
    final taste = this.taste();
    final ids = {for (final song in pool) song['ytid'].toString()};
    final artists = {for (final song in pool) artistKey(song['artist'])};

    final seeds = <String, double>{
      for (final seed
          in taste.seeds
              .where(
                (s) =>
                    ids.contains(s.song['ytid']?.toString()) ||
                    artists.contains(artistKey(s.song['artist'])),
              )
              .take(6))
        seed.song['ytid'].toString(): seed.weight,
    };
    final radios = await _radiosOf(seeds.keys);
    if (generation != _generation || !_enabled) return const [];
    final similar = scoreRadios(
      taste: taste,
      radios: radios,
      seedWeights: seeds,
      accept: (song) => ids.contains(song['ytid']?.toString()),
    );
    final scored = <String, ({Map song, double score})>{
      for (final song in pool)
        song['ytid'].toString(): (
          song: song,
          score:
              0.25 * min((song['n'] as num? ?? 1).toDouble(), 4) +
              taste.affinity(song) +
              0.5 * (similar[song['ytid'].toString()]?.score ?? 0),
        ),
    };
    return assembleQueue(
      taste: taste,
      scored: scored,
      discovery: discovery ?? moodsTuning.value.discovery,
      length: length,
      perArtist: 2,
      excludedArtists: await _excludedArtists(),
      random: random,
    );
  }

  /// Starts [mood] playing. The queue keeps going on its own after it.
  Future<bool> play(Mood mood) async {
    final songs = await this.mood(mood);
    if (!_enabled || songs.isEmpty) return false;
    await audioHandler.playPlaylistSong(
      playlist: {'title': moodLabel(_l10n, mood), 'list': songs},
      songIndex: 0,
      shuffle: false,
      keepGoing: true,
    );
    return true;
  }

  /// Starts a radio from [seeds], as YouTube Music would after them but
  /// shaped like the Mix: the user's discovery, artists spaced out, a queue
  /// that never runs out. An artist's radio passes its top songs, in order,
  /// and lets [perArtist] be higher so the artist comes up more.
  ///
  /// YouTube Music has no radio for what isn't music (rain, a talk): then
  /// the first seed plays and the automatic picker follows it, as it
  /// follows anything.
  Future<bool> playRadio(
    List<Map> seeds, {
    required String title,
    int perArtist = 3,
  }) async {
    if (!_online || seeds.isEmpty) return false;
    final generation = _generation;
    final songs = seeds.where(_isSong).take(4).toList();
    final weights = {
      for (final (i, song) in songs.indexed)
        song['ytid'].toString(): 1.0 - i * 0.15,
    };
    final taste = this.taste();
    final seedArtists = {for (final song in songs) artistKey(song['artist'])};
    final radios = await _radiosOf(weights.keys);
    if (!_online || generation != _generation) return false;
    final queue = assembleQueue(
      taste: taste,
      scored: scoreRadios(taste: taste, radios: radios, seedWeights: weights),
      discovery: moodsTuning.value.discovery,
      length: 50,
      perArtist: perArtist,
      // Asking for an artist's radio overrides leaving its genre out.
      excludedArtists: (await _excludedArtists()).difference(seedArtists),
    );
    if (!_online || generation != _generation) return false;
    await audioHandler.playPlaylistSong(
      playlist: {
        'title': title,
        'list': queue.isEmpty ? [seeds.first] : queue,
      },
      songIndex: 0,
      shuffle: false,
      keepGoing: true,
    );
    return true;
  }

  /// Up to 8 of the strongest seeds, at most 2 per artist, plus 3 from
  /// further down for variety.
  Map<String, double> _pickSeeds(Taste taste, Random random) {
    final picked = <String, double>{};
    final perArtist = <String, int>{};
    final rest = <({Map song, double weight})>[];
    for (final seed in taste.seeds.take(40)) {
      final key = artistKey(seed.song['artist']);
      if (picked.length < 8 && (perArtist[key] ?? 0) < 2) {
        perArtist[key] = (perArtist[key] ?? 0) + 1;
        picked[seed.song['ytid'].toString()] = seed.weight;
      } else {
        rest.add(seed);
      }
    }
    rest.shuffle(random);
    for (final seed in rest.take(3)) {
      picked[seed.song['ytid'].toString()] = seed.weight;
    }
    return picked;
  }

  Future<Map<String, List<Map>>> _radiosOf(Iterable<String> ids) async {
    final list = ids.toList();
    final generation = _generation;
    final radios = await _inBatches(
      list,
      (id) => generation == _generation && _online
          ? radio(id)
          : Future.value(<Map>[]),
    );
    return {
      for (var i = 0; i < list.length; i++)
        if (radios[i].isNotEmpty) list[i]: radios[i],
    };
  }

  // ---------------------------------------------------------------------
  // YouTube Music catalog: moods, genres and charts.

  /// YouTube Music's moods and genres. Their params expire, so they are read
  /// again at most once a session.
  Future<List<MusicMood>>? _catalog;
  Future<List<MusicMood>> _moods() {
    final generation = _generation;
    final region = country;
    return _catalog ??= _run(_moodsTask(region)).catchError((Object error) {
      if (generation == _generation) _catalog = null;
      throw error;
    });
  }

  static const _poolDays = 3;

  /// The songs of YouTube Music's playlists for [mood], each with how many
  /// of those playlists list it (`n`). Cached for a few days.
  Future<List<Map>> _moodPool(Mood mood) =>
      _cachedPool('moods:pool:${mood.name}', mood.youtubeTitle!, genre: false);

  Future<List<Map>> _cachedPool(
    String key,
    String title, {
    required bool genre,
    int playlists = 10,
  }) async {
    final generation = _generation;
    final cached = _cache.get(key);
    if (cached is Map && _fresh(cached, const Duration(days: _poolDays))) {
      return _maps(cached['songs']);
    }
    try {
      final moods = await _moods();
      final entry = moods.firstWhere(
        (m) => m.isGenre == genre && m.title == title,
      );
      final params = entry.params;
      final region = country;
      if (generation != _generation || !_enabled) return const [];
      final pool = await _run(_poolTask(params, region, playlists));
      if (generation != _generation || !_enabled) return const [];
      if (pool.isNotEmpty) {
        await _cache.put(key, {
          'at': DateTime.now().toIso8601String(),
          'songs': pool,
        });
      }
      return pool;
    } catch (e, stackTrace) {
      if (e is MoodsCancelled || generation != _generation) return const [];
      logger.log('Moods pool failed: $title', error: e, stackTrace: stackTrace);
      return cached is Map ? _maps(cached['songs']) : const [];
    }
  }

  /// The genres the user listens to, strongest first. Each genre's artists
  /// come from three of its YouTube Music playlists, read once a week.
  Future<List<DetectedGenre>> detectedGenres() async {
    if (!_enabled) return const [];
    final genres = await _genreArtists();
    final taste = this.taste();
    final detected = <DetectedGenre>[];
    for (final genre in genres) {
      final matched =
          (genre['artists'] as List)
              .map((e) => e.toString())
              .where(taste.artists.containsKey)
              .toList()
            ..sort((a, b) => taste.artists[b]!.compareTo(taste.artists[a]!));
      final score = matched.fold<double>(
        0,
        (sum, a) => sum + taste.artists[a]!,
      );
      if (matched.length >= 2 && score >= 0.5) {
        detected.add((
          title: genre['title'].toString(),
          label: genre['label'].toString(),
          score: score,
          artists: matched,
        ));
      }
    }
    return detected..sort((a, b) => b.score.compareTo(a.score));
  }

  static const _genresKey = 'moods:genres';

  /// Entries of the genres page that gather any style.
  static const _notGenres = {
    'Decades',
    'Family',
    'Seasonal',
    'Soundtracks & musicals',
  };

  /// A reading in progress, shared by whoever asks meanwhile: each one is
  /// about a hundred requests.
  Future<List<Map>>? _readingGenres;

  Future<List<Map>> _genreArtists() {
    final cached = _cache.get(_genresKey);
    if (!_enabled)
      return Future.value(cached is Map ? _maps(cached['genres']) : const []);
    final generation = _generation;
    if (cached is Map &&
        cached['language'] == languageSetting.languageCode &&
        _fresh(cached, const Duration(days: 7))) {
      return Future.value(_maps(cached['genres']));
    }
    return _readingGenres ??= _readGenres(cached).whenComplete(() {
      if (generation == _generation) _readingGenres = null;
    });
  }

  Future<List<Map>> _readGenres(Object? cached) async {
    final generation = _generation;
    try {
      final region = country;
      final language = languageSetting.languageCode;
      final result = await _run(_genresTask(region, language));
      if (generation != _generation || !_enabled) return const [];
      if (result.isNotEmpty) {
        await _cache.put(_genresKey, {
          'at': DateTime.now().toIso8601String(),
          'language': languageSetting.languageCode,
          'genres': result,
        });
      }
      return result;
    } catch (e, stackTrace) {
      if (e is MoodsCancelled || generation != _generation) return const [];
      logger.log('Moods genres failed', error: e, stackTrace: stackTrace);
      return cached is Map ? _maps(cached['genres']) : const [];
    }
  }

  /// Artists of the genres the user left out, unless another genre they
  /// listen to claims them too. Reads the genres already known, however old:
  /// a tap on a mood never waits on the minute it takes to read them again.
  Future<Set<String>> _excludedArtists() async {
    final tuning = moodsTuning.value;
    if (tuning.excludedGenres.isEmpty) return tuning.blockedArtists;
    final cached = _cache.get(_genresKey);
    if (cached is! Map || !_fresh(cached, const Duration(days: 7))) {
      unawaited(_genreArtists());
    }
    return _cachedExcludedArtists();
  }

  Set<String> _cachedExcludedArtists() {
    final tuning = moodsTuning.value;
    if (tuning.excludedGenres.isEmpty) return tuning.blockedArtists;
    final cached = _cache.get(_genresKey);
    final genres = cached is Map ? _maps(cached['genres']) : const <Map>[];
    final out = <String>{};
    final kept = <String>{};
    for (final genre in genres) {
      final artists = (genre['artists'] as List).map((e) => e.toString());
      (tuning.excludedGenres.contains(genre['title']) ? out : kept).addAll(
        artists,
      );
    }
    return {...tuning.blockedArtists, ...out.difference(kept)};
  }

  Future<List<Map>> _chartSongs([String chart = 'ZZ']) async {
    final key = 'moods:chart:$chart';
    final generation = _generation;
    final cached = _cache.get(key);
    if (cached is Map && _fresh(cached, const Duration(hours: 12))) {
      return _maps(cached['songs']);
    }
    try {
      if (!_enabled) return cached is Map ? _maps(cached['songs']) : const [];
      final songs = await _run(_chartTask(chart));
      if (generation != _generation || !_enabled) return const [];
      if (songs.isNotEmpty) {
        await _cache.put(key, {
          'at': DateTime.now().toIso8601String(),
          'songs': songs,
        });
      }
      return songs;
    } catch (e, stackTrace) {
      if (e is MoodsCancelled || generation != _generation) return const [];
      logger.log('Moods chart failed', error: e, stackTrace: stackTrace);
      return cached is Map ? _maps(cached['songs']) : const [];
    }
  }

  // ---------------------------------------------------------------------
  // Zenify's own playlists.

  static const _playlistPrefix = 'zenify:';

  static bool isZenifyPlaylist(Object? id) =>
      id?.toString().startsWith(_playlistPrefix) ?? false;

  /// The playlists Zenify makes for the user right now, each refreshed on
  /// its own schedule. One that can't be refreshed keeps its last songs; one
  /// that was never made is left out. Each one comes as soon as it is
  /// ready: the first ones of a day take a few seconds each.
  Stream<List<Map>> playlists() async* {
    if (!_enabled) return;
    final generation = _generation;
    final tuning = _tuningSignature;
    bool active() =>
        _enabled && generation == _generation && tuning == _tuningSignature;
    final ids = [
      '${_playlistPrefix}daily',
      '${_playlistPrefix}moment',
      '${_playlistPrefix}new',
      '${_playlistPrefix}discoveries',
      '${_playlistPrefix}most-played',
      for (final genre
          in (await _detectedGenresIfReady())
              .where((g) => !moodsTuning.value.excludedGenres.contains(g.title))
              .take(2))
        '${_playlistPrefix}genre:${genre.title}',
      for (final month in _addictionMonths())
        '${_playlistPrefix}addictions:$month',
      '${_playlistPrefix}top:ZZ',
      if (country case final c? when c != 'ZZ') '${_playlistPrefix}top:$c',
    ];
    if (!active()) return;
    // What is current shows at once; the rest is made once the app has
    // opened, so the first playlists of a day don't compete with it.
    final made = <String, Map>{};
    final stale = <String>[];
    for (final id in ids) {
      final current = _currentPlaylist(id);
      current == null ? stale.add(id) : made[id] = current;
    }
    List<Map> inOrder() => [for (final id in ids) ?made[id]];
    if (made.isNotEmpty) yield inOrder();
    if (stale.isNotEmpty) {
      await Future<void>.delayed(const Duration(seconds: 4));
      for (final id in stale) {
        if (!active()) return;
        final playlist = await this.playlist(id);
        if (!active()) return;
        if (playlist == null) continue;
        made[id] = playlist;
        yield inOrder();
      }
    }
    // Last, and in the background: genres are read again once a week.
    if (active() && !_genresFresh) {
      unawaited(detectedGenres().catchError((Object _) => <DetectedGenre>[]));
    }
  }

  bool get _genresFresh {
    final cached = _cache.get(_genresKey);
    return cached is Map && _fresh(cached, const Duration(days: 7));
  }

  /// The detected genres when they are already known, without reading them.
  Future<List<DetectedGenre>> _detectedGenresIfReady() async =>
      _genresFresh ? detectedGenres() : const [];

  /// What the library shows for a saved playlist without waiting: its last
  /// songs, or just its title when this device never made it (after a
  /// restore or a sync). Opening it makes it.
  Map cachedPlaylist(String id) {
    final cached = _cache.get('moods:playlist:$id');
    if (cached is Map) return _playlistMap(cached);
    return {'ytid': id, 'title': _titleOf(id), 'source': 'zenify', 'list': []};
  }

  String _titleOf(String id) {
    final l10n = _l10n;
    final kind = id.substring(_playlistPrefix.length);
    if (kind.startsWith('genre:')) return kind.substring('genre:'.length);
    if (kind.startsWith('top:')) {
      return kind == 'top:ZZ' ? l10n.zenifyTopGlobal : l10n.zenifyTopCountry;
    }
    if (kind.startsWith('addictions:')) {
      final date = DateTime.tryParse('${kind.substring(11)}-01');
      return date == null
          ? l10n.zenifyMostPlayed
          : l10n.zenifyAddictions(
              DateFormat.MMMM(languageSetting.toString()).format(date),
            );
    }
    return switch (kind) {
      'daily' => l10n.zenifyDaily,
      'moment' => momentTitle(l10n, DateTime.now()),
      'new' => l10n.zenifyNewForYou,
      'discoveries' => l10n.zenifyDiscoveries,
      _ => l10n.zenifyMostPlayed,
    };
  }

  /// A Zenify playlist from its cache while it is current, else null.
  Map? _currentPlaylist(String id) {
    final cached = _cache.get('moods:playlist:$id');
    if (cached is Map &&
        cached['language'] == languageSetting.languageCode &&
        cached['tuning'] == _tuningSignature &&
        (DateTime.tryParse('${cached['until']}')?.isAfter(DateTime.now()) ??
            false)) {
      return _playlistMap(cached);
    }
    return null;
  }

  /// One Zenify playlist by id, from its cache while it is current.
  Future<Map?> playlist(String id) async {
    if (!isZenifyPlaylist(id)) return null;
    final generation = _generation;
    final tuning = _tuningSignature;
    if (_currentPlaylist(id) case final current?) return current;
    final cacheKey = 'moods:playlist:$id';
    final cached = _cache.get(cacheKey);
    if (!_enabled) return cached is Map ? _playlistMap(cached) : null;
    final now = DateTime.now();
    try {
      final made = await _make(id.substring(_playlistPrefix.length), now);
      if (!_enabled || generation != _generation) return null;
      if (tuning != _tuningSignature) return await playlist(id);
      if (made == null || (made['list'] as List).length < 8) {
        return cached is Map ? _playlistMap(cached) : null;
      }
      final stored = {
        ...made,
        'ytid': id,
        'language': languageSetting.languageCode,
        'tuning': tuning,
      };
      await _cache.put(cacheKey, stored);
      return _playlistMap(stored);
    } catch (e, stackTrace) {
      if (e is MoodsCancelled || generation != _generation) return null;
      logger.log(
        'Zenify playlist $id failed',
        error: e,
        stackTrace: stackTrace,
      );
      return cached is Map ? _playlistMap(cached) : null;
    }
  }

  Map _playlistMap(Map stored) {
    final blocked = _cachedExcludedArtists();
    final songs = blocked.isEmpty
        ? _maps(stored['list'])
        : _maps(stored['list'])
              .where((song) => !blocked.contains(artistKey(song['artist'])))
              .toList();
    // Recap songs may carry an empty artwork.
    final covers = {
      for (final song in songs.take(12))
        if (song['image'] case final String image when image.isNotEmpty) image,
    }.take(4).toList();
    return {
      ...stored,
      'list': songs,
      'source': 'zenify',
      'image': covers.firstOrNull,
      'covers': covers,
    };
  }

  Future<Map?> _make(String kind, DateTime now) async {
    final l10n = _l10n;
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final daySeed = now.year * 10000 + now.month * 100 + now.day;
    Map made(
      String title,
      String description,
      List<Map> list,
      DateTime until,
    ) => {
      'title': title,
      'description': description,
      'list': list,
      'until': until.toIso8601String(),
    };

    switch (kind) {
      case 'daily':
        return made(
          l10n.zenifyDaily,
          l10n.zenifyChangesDaily,
          await mix(length: 50, random: Random(daySeed)),
          tomorrow,
        );
      case 'moment':
        final slot = now.hour ~/ 4;
        final start = DateTime(now.year, now.month, now.day, slot * 4);
        final mood = _momentMood(slot, now.weekday);
        return made(
          momentTitle(l10n, now),
          l10n.zenifyChangesEvery4Hours,
          await this.mood(mood, random: Random(daySeed * 10 + slot)),
          start.add(const Duration(hours: 4)),
        );
      case 'new':
        return made(
          l10n.zenifyNewForYou,
          l10n.zenifyNewForYouDescription,
          await mix(discovery: Discovery.onlyNew, random: Random(daySeed + 1)),
          tomorrow,
        );
      case 'discoveries':
        return made(
          l10n.zenifyDiscoveries,
          l10n.zenifyDiscoveriesDescription,
          _discoveries(),
          tomorrow,
        );
      case 'most-played':
        return made(
          l10n.zenifyMostPlayed,
          l10n.zenifyMostPlayedDescription,
          _mostPlayed(),
          tomorrow,
        );
    }
    if (kind.startsWith('genre:')) {
      final title = kind.substring('genre:'.length);
      final genres = await _genreArtists();
      final genre = genres.firstWhere(
        (g) => g['title'] == title,
        orElse: () => {'title': title, 'label': title},
      );
      final pool = await _cachedPool(
        'moods:genre:$title',
        title,
        genre: true,
        playlists: 8,
      );
      return made(
        genre['label'].toString(),
        l10n.zenifyChangesDaily,
        await _fromPool(pool, length: 40, random: Random(daySeed + 2)),
        tomorrow,
      );
    }
    if (kind.startsWith('addictions:')) {
      final month = kind.substring('addictions:'.length);
      final songs = listeningStatsService.monthTopSongs(month, limit: 30);
      final date = DateTime.tryParse('$month-01');
      if (date == null) return null;
      return made(
        l10n.zenifyAddictions(
          DateFormat.MMMM(languageSetting.toString()).format(date),
        ),
        l10n.zenifyAddictionsDescription,
        songs.where(_isSong).toList(),
        now.add(const Duration(days: 30)),
      );
    }
    if (kind.startsWith('top:')) {
      final chart = kind.substring('top:'.length);
      final songs = await _chartSongs(chart);
      return made(
        chart == 'ZZ' ? l10n.zenifyTopGlobal : l10n.zenifyTopCountry,
        l10n.zenifyTopDescription,
        songs,
        now.add(const Duration(hours: 12)),
      );
    }
    return null;
  }

  /// Late night winds down, mornings wake up, Friday and Saturday nights
  /// party.
  static Mood _momentMood(int slot, int weekday) {
    final weekend = weekday >= DateTime.friday;
    return switch (slot) {
      0 => Mood.sleep,
      1 => Mood.chill,
      2 => Mood.energize,
      3 => weekday <= DateTime.friday ? Mood.focus : Mood.feelGood,
      4 => weekend ? Mood.feelGood : Mood.commute,
      _ => weekend ? Mood.party : Mood.chill,
    };
  }

  /// Songs first heard in the last two weeks: played lately and in no
  /// earlier recap month.
  List<Map> _discoveries() {
    final months = _recapMonths();
    final older = <String>{
      for (final month in months.skip(1))
        for (final id in month.keys) id.toString(),
    };
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    final current = months.isEmpty ? const <Map>[] : months.first.values;
    final fromRecap = [
      for (final entry in current.whereType<Map>())
        if (!older.contains(entry['ytid']?.toString()) &&
            (DateTime.tryParse('${entry['lastPlayed']}')?.isAfter(cutoff) ??
                false))
          entry,
    ]..sort((a, b) => '${b['lastPlayed']}'.compareTo('${a['lastPlayed']}'));
    final ids = <String>{};
    return [
      for (final song in [
        ...fromRecap,
        ...userRecentlyPlayed.value.whereType<Map>(),
      ])
        if (!older.contains(song['ytid']?.toString()) &&
            _isSong(song) &&
            ids.add(song['ytid'].toString()))
          song,
    ].take(50).toList();
  }

  /// The most played songs of the last month or so.
  List<Map> _mostPlayed() {
    final months = _recapMonths().take(2).toList();
    final seconds = <String, double>{};
    final songs = <String, Map>{};
    for (var i = 0; i < months.length; i++) {
      for (final entry in months[i].values.whereType<Map>()) {
        final id = entry['ytid']?.toString() ?? '';
        if (id.isEmpty || !_isSong(entry)) continue;
        seconds[id] =
            (seconds[id] ?? 0) + (entry['seconds'] as num? ?? 0) / (i + 1);
        songs[id] = entry;
      }
    }
    final ranked = seconds.keys.toList()
      ..sort((a, b) => seconds[b]!.compareTo(seconds[a]!));
    return [for (final id in ranked.take(50)) songs[id]!];
  }

  /// Up to three previous recap months with enough songs to be a playlist.
  List<String> _addictionMonths() {
    final keys = listeningStatsService.availableMonthKeys.toList()
      ..sort((a, b) => b.compareTo(a));
    final now = DateTime.now();
    final current = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    return keys
        .where(
          (k) =>
              k != current &&
              listeningStatsService.monthTopSongs(k, limit: 30).length >= 10,
        )
        .take(3)
        .toList();
  }

  /// Drops what the Moods would play from the cache, e.g. when they are
  /// turned off.
  Future<void> clearCache() async {
    _cancelPending();
    _notSongs.clear();
    final keys = _cache.keys.where((k) => k.toString().startsWith('moods:'));
    await _cache.deleteAll(keys.toList());
  }

  // ---------------------------------------------------------------------

  static bool _fresh(Map cached, Duration validity) {
    final at = DateTime.tryParse('${cached['at']}');
    return at != null && DateTime.now().difference(at) < validity;
  }

  static List<Map> _maps(Object? raw) =>
      raw is List ? raw.whereType<Map>().toList() : const [];

  /// Runs [task] on [items] a few at a time, keeping their order.
  static Future<List<R>> _inBatches<T, R>(
    List<T> items,
    Future<R> Function(T item) task, {
    int batch = 4,
  }) async {
    final results = <R>[];
    for (var i = 0; i < items.length; i += batch) {
      results.addAll(await Future.wait(items.skip(i).take(batch).map(task)));
    }
    return results;
  }
}

typedef _Task<T> = Future<T> Function(MusicClient music);

/// A top-level factory keeps the worker closure free of service state.
Future<T> Function() _musicTask<T>(_Task<T> task) => () async {
  final http = YoutubeHttpClient();
  try {
    return await task(MusicClient(http));
  } finally {
    http.close();
  }
};

/// A track's radio, and whether YouTube Music lists the track itself as
/// music: when it doesn't, its radio would be more of it.
_Task<({bool seedIsSong, List<Map> songs})> _radioTask(
  String id,
  String? country,
) => (music) async {
  final tracks = await music.getRadio(id, country: country);
  final seed = tracks.firstOrNull;
  return (
    seedIsSong: seed == null || seed.video.id.value != id || _counts(seed),
    songs: _songsOf(tracks),
  );
};

_Task<List<MusicMood>> _moodsTask(String? country) =>
    (music) => music.getMoods(country: country);

_Task<List<Map>> _poolTask(String params, String? country, int count) =>
    (music) => _fetchPool(music, params, country, count);

_Task<List<Map>> _genresTask(String? country, String language) =>
    (music) => _fetchGenres(music, country, language);

_Task<List<Map>> _chartTask(String chart) =>
    (music) => _fetchChart(music, chart);

/// The songs of [count] of the playlists YouTube Music curates for a mood
/// or genre ([params]), each with how many of them list it (`n`). One
/// playlist from each shelf in turn: shelves split a mood by style (chill
/// pop, muted jazz…), so the pool covers them all.
Future<List<Map>> _fetchPool(
  MusicClient music,
  String params,
  String? country,
  int count,
) async {
  final shelves = await music.getMoodPlaylists(params, country: country);
  final byShelf = <String?, List<MusicPlaylistSummary>>{};
  for (final playlist in shelves) {
    (byShelf[playlist.shelf] ??= []).add(playlist);
  }
  final chosen = <MusicPlaylistSummary>[];
  for (var round = 0; chosen.length < count; round++) {
    final before = chosen.length;
    for (final group in byShelf.values) {
      if (round < group.length && chosen.length < count) {
        chosen.add(group[round]);
      }
    }
    if (chosen.length == before) break;
  }
  final lists = await MoodsService._inBatches(
    chosen,
    (p) => music
        .getPlaylistTracks(p.id, country: country)
        .then(_songsOf)
        .catchError((Object _) => <Map>[]),
  );
  final songs = <String, Map>{};
  for (final list in lists) {
    for (final song in list) {
      final id = song['ytid'].toString();
      final existing = songs[id];
      songs[id] = existing == null
          ? {...song, 'n': 1}
          : {...existing, 'n': (existing['n'] as int) + 1};
    }
  }
  return songs.values.toList();
}

/// Each genre (gathering entries left out) with its name in [language] and
/// the artists of three of its playlists.
Future<List<Map>> _fetchGenres(
  MusicClient music,
  String? country,
  String language,
) async {
  final genres = (await music.getMoods(country: country))
      .where((m) => m.isGenre && !MoodsService._notGenres.contains(m.title))
      .toList();
  final labels = {
    for (final m in await music.getMoods(country: country, language: language))
      m.params: m.title,
  };
  final artists = await MoodsService._inBatches(genres, (genre) async {
    try {
      final playlists = await music.getMoodPlaylists(
        genre.params,
        country: country,
      );
      final keys = <String>{};
      for (final playlist in playlists.take(3)) {
        for (final track in await music.getPlaylistTracks(playlist.id)) {
          keys.add(artistKey(track.video.author));
        }
      }
      return keys..remove('');
    } catch (_) {
      return <String>{};
    }
  }, batch: 3);
  return [
    for (var i = 0; i < genres.length; i++)
      if (artists[i].isNotEmpty)
        {
          'title': genres[i].title,
          'label': labels[genres[i].params] ?? genres[i].title,
          'artists': artists[i].toList(),
        },
  ];
}

/// The songs of the top 100 chart of [chart] (`ZZ` for global).
Future<List<Map>> _fetchChart(MusicClient music, String chart) async {
  final charts = await music.getCharts(country: chart);
  final top = charts.firstWhere(
    (p) => p.title.toLowerCase().startsWith('top 100'),
    orElse: () => charts.first,
  );
  return _songsOf(await music.getPlaylistTracks(top.id));
}

/// Whether YouTube Music lists [track] as music: a release's audio or an
/// official video. That is the whole quality filter of the Moods.
bool _counts(MusicTrack track) =>
    track.type == MusicVideoType.song ||
    track.type == MusicVideoType.officialVideo;

/// YouTube Music tracks as song maps, only those it lists as music.
List<Map> _songsOf(List<MusicTrack> tracks) => [
  for (final track in tracks)
    if (_counts(track)) trackToSong(track),
];

/// A YouTube Music track as the song map the rest of the app plays.
Map<String, dynamic> trackToSong(MusicTrack track) {
  final video = track.video;
  final art = track.type == MusicVideoType.song ? track.thumbnailUrl : null;
  String? sized(int px) =>
      art?.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w$px-h$px');
  final title = formatSongTitle(video.title);
  return {
    'ytid': video.id.value,
    'title': title.isEmpty ? video.title : title,
    'artist': video.author,
    if (track.artistId != null) 'artistId': track.artistId,
    'image': sized(544) ?? video.thumbnails.standardResUrl,
    'lowResImage': sized(226) ?? video.thumbnails.lowResUrl,
    'highResImage': sized(1080) ?? video.thumbnails.maxResUrl,
    'duration': video.duration?.inSeconds,
    'isLive': false,
  };
}

String moodLabel(AppLocalizations l10n, Mood mood) => switch (mood) {
  Mood.mix => l10n.moodMix,
  Mood.feelGood => l10n.moodFeelGood,
  Mood.chill => l10n.moodChill,
  Mood.energize => l10n.moodEnergize,
  Mood.focus => l10n.moodFocus,
  Mood.party => l10n.moodParty,
  Mood.romance => l10n.moodRomance,
  Mood.sad => l10n.moodSad,
  Mood.workout => l10n.moodWorkout,
  Mood.commute => l10n.moodCommute,
  Mood.sleep => l10n.moodSleep,
};

/// "Sunday night", "Madrugada de domingo": the part of the day and the day.
String momentTitle(AppLocalizations l10n, DateTime now) {
  final part = switch (now.hour ~/ 4) {
    0 => l10n.momentLateNight,
    1 => l10n.momentDawn,
    2 => l10n.momentMorning,
    3 => l10n.momentAfternoon,
    4 => l10n.momentEvening,
    _ => l10n.momentNight,
  };
  final day = DateFormat.EEEE(languageSetting.toString()).format(now);
  return l10n.zenifyMoment(day, part);
}

final moodsService = MoodsService();
