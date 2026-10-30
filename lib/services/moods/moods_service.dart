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
import 'package:musify/services/artist_service.dart' show ytMusicClient;
import 'package:musify/services/common_services.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/moods/mix_engine.dart';
import 'package:musify/services/moods/moods_preferences.dart';
import 'package:musify/services/moods/taste.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/formatter.dart';
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
  MusicClient get _music => ytMusicClient.music;
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

  /// The user's taste right now, from the library.
  Taste taste() {
    final kept = <Map>[
      for (final playlist in userCustomPlaylists.value)
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
      blockedArtists: moodsTuning.value.blockedArtists,
    );
  }

  /// The songs of each recap month, the current one first.
  List<Map> _recapMonths() {
    final keys = listeningStatsService.availableMonthKeys.toList()
      ..sort((a, b) => b.compareTo(a));
    return [
      for (final key in keys)
        if (listeningStatsService.monthStats(key)?['songs'] case final Map s) s,
    ];
  }

  /// What YouTube Music plays after [id], songs only.
  Future<List<Map>> radio(String id) {
    if (_radios.length > 200) _radios.clear();
    return _radios[id] ??= _music
        .getRadio(id, country: country)
        .then(_songsOf)
        .catchError((Object error) {
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
    final shuffle = random ?? Random();
    final taste = this.taste();
    var seeds = _pickSeeds(taste, shuffle);
    if (seeds.isEmpty) {
      // A new install: start from what is popular here, and learn.
      final top = await _chartSongs();
      seeds = {for (final song in top.take(6)) song['ytid'].toString(): 0.5};
    }
    final radios = await _radiosOf(seeds.keys);
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
    if (mood == Mood.mix) return mix(length: length, random: random);
    final pool = await _moodPool(mood);
    if (pool.isEmpty) return const [];
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
    final similar = scoreRadios(
      taste: taste,
      radios: await _radiosOf(seeds.keys),
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
    if (songs.isEmpty) return false;
    await audioHandler.playPlaylistSong(
      playlist: {'title': moodLabel(_l10n, mood), 'list': songs},
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
    final radios = await _inBatches(list, radio);
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
  Future<List<MusicMood>> _moods() =>
      _catalog ??= _music.getMoods(country: country).catchError((Object error) {
        _catalog = null;
        throw error;
      });

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
    final cached = _cache.get(key);
    if (cached is Map && _fresh(cached, const Duration(days: _poolDays))) {
      return _maps(cached['songs']);
    }
    try {
      final moods = await _moods();
      final entry = moods.firstWhere(
        (m) => m.isGenre == genre && m.title == title,
      );
      final shelves = await _music.getMoodPlaylists(
        entry.params,
        country: country,
      );
      // One playlist from each shelf in turn: shelves split a mood by
      // style (chill pop, muted jazz…), so the pool covers them all.
      final byShelf = <String?, List<MusicPlaylistSummary>>{};
      for (final playlist in shelves) {
        (byShelf[playlist.shelf] ??= []).add(playlist);
      }
      final chosen = <MusicPlaylistSummary>[];
      for (var round = 0; chosen.length < playlists; round++) {
        final before = chosen.length;
        for (final group in byShelf.values) {
          if (round < group.length && chosen.length < playlists) {
            chosen.add(group[round]);
          }
        }
        if (chosen.length == before) break;
      }
      final lists = await _inBatches(
        chosen,
        (p) => _music
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
      final pool = songs.values.toList();
      if (pool.isNotEmpty) {
        await _cache.put(key, {
          'at': DateTime.now().toIso8601String(),
          'songs': pool,
        });
      }
      return pool;
    } catch (e, stackTrace) {
      logger.log('Moods pool failed: $title', error: e, stackTrace: stackTrace);
      return cached is Map ? _maps(cached['songs']) : const [];
    }
  }

  /// The genres the user listens to, strongest first. Each genre's artists
  /// come from three of its YouTube Music playlists, read once a week.
  Future<List<DetectedGenre>> detectedGenres() async {
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

  Future<List<Map>> _genreArtists() async {
    final cached = _cache.get(_genresKey);
    if (cached is Map &&
        cached['language'] == languageSetting.languageCode &&
        _fresh(cached, const Duration(days: 7))) {
      return _maps(cached['genres']);
    }
    try {
      final genres = (await _moods())
          .where((m) => m.isGenre && !_notGenres.contains(m.title))
          .toList();
      final labels = {
        for (final m in await _music.getMoods(
          country: country,
          language: languageSetting.languageCode,
        ))
          m.params: m.title,
      };
      final artists = await _inBatches(genres, (genre) async {
        try {
          final playlists = await _music.getMoodPlaylists(
            genre.params,
            country: country,
          );
          final keys = <String>{};
          for (final playlist in playlists.take(3)) {
            final tracks = await _music.getPlaylistTracks(playlist.id);
            for (final track in tracks) {
              keys.add(artistKey(track.video.author));
            }
          }
          return keys..remove('');
        } catch (_) {
          return <String>{};
        }
      }, batch: 3);
      final result = [
        for (var i = 0; i < genres.length; i++)
          if (artists[i].isNotEmpty)
            {
              'title': genres[i].title,
              'label': labels[genres[i].params] ?? genres[i].title,
              'artists': artists[i].toList(),
            },
      ];
      if (result.isNotEmpty) {
        await _cache.put(_genresKey, {
          'at': DateTime.now().toIso8601String(),
          'language': languageSetting.languageCode,
          'genres': result,
        });
      }
      return result;
    } catch (e, stackTrace) {
      logger.log('Moods genres failed', error: e, stackTrace: stackTrace);
      return cached is Map ? _maps(cached['genres']) : const [];
    }
  }

  /// Artists of the genres the user left out, unless another genre they
  /// listen to claims them too.
  Future<Set<String>> _excludedArtists() async {
    final tuning = moodsTuning.value;
    if (tuning.excludedGenres.isEmpty) return tuning.blockedArtists;
    final genres = await _genreArtists();
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
    final cached = _cache.get(key);
    if (cached is Map && _fresh(cached, const Duration(hours: 12))) {
      return _maps(cached['songs']);
    }
    try {
      final charts = await _music.getCharts(country: chart);
      final top = charts.firstWhere(
        (p) => p.title.toLowerCase().startsWith('top 100'),
        orElse: () => charts.first,
      );
      final songs = _songsOf(await _music.getPlaylistTracks(top.id));
      if (songs.isNotEmpty) {
        await _cache.put(key, {
          'at': DateTime.now().toIso8601String(),
          'songs': songs,
        });
      }
      return songs;
    } catch (e, stackTrace) {
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
    final ids = [
      '${_playlistPrefix}daily',
      '${_playlistPrefix}moment',
      '${_playlistPrefix}new',
      '${_playlistPrefix}discoveries',
      '${_playlistPrefix}most-played',
      for (final genre in (await _detectedGenresIfReady()).take(2))
        '${_playlistPrefix}genre:${genre.title}',
      for (final month in _addictionMonths())
        '${_playlistPrefix}addictions:$month',
      '${_playlistPrefix}top:ZZ',
      if (country case final c? when c != 'ZZ') '${_playlistPrefix}top:$c',
    ];
    final result = <Map>[];
    for (final id in ids) {
      final made = await playlist(id);
      if (made == null) continue;
      result.add(made);
      yield List.of(result);
    }
  }

  /// The detected genres when they are already known; otherwise they are
  /// worked out in the background, for the next time, so Home never waits
  /// on the minute it takes.
  Future<List<DetectedGenre>> _detectedGenresIfReady() async {
    final cached = _cache.get(_genresKey);
    if (cached is Map && _fresh(cached, const Duration(days: 7))) {
      return detectedGenres();
    }
    unawaited(detectedGenres().catchError((Object _) => <DetectedGenre>[]));
    return const [];
  }

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

  /// One Zenify playlist by id, from its cache while it is current.
  Future<Map?> playlist(String id) async {
    final cacheKey = 'moods:playlist:$id';
    final cached = _cache.get(cacheKey);
    final now = DateTime.now();
    if (cached is Map &&
        cached['language'] == languageSetting.languageCode &&
        now.isBefore(DateTime.parse(cached['until'].toString()))) {
      return _playlistMap(cached);
    }
    try {
      final made = await _make(id.substring(_playlistPrefix.length), now);
      if (made == null || (made['list'] as List).length < 8) {
        return cached is Map ? _playlistMap(cached) : null;
      }
      final stored = {
        ...made,
        'ytid': id,
        'language': languageSetting.languageCode,
      };
      await _cache.put(cacheKey, stored);
      return _playlistMap(stored);
    } catch (e, stackTrace) {
      logger.log(
        'Zenify playlist $id failed',
        error: e,
        stackTrace: stackTrace,
      );
      return cached is Map ? _playlistMap(cached) : null;
    }
  }

  Map _playlistMap(Map stored) {
    final songs = _maps(stored['list']);
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
        songs.where(looksLikeSong).toList(),
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
            looksLikeSong(song) &&
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
        if (id.isEmpty || !looksLikeSong(entry)) continue;
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
    _radios.clear();
    _catalog = null;
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

/// YouTube Music tracks as song maps, user uploads and non-songs left out.
List<Map> _songsOf(List<MusicTrack> tracks) => [
  for (final track in tracks)
    if (track.type != MusicVideoType.userUpload)
      if (trackToSong(track) case final song when looksLikeSong(song)) song,
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
