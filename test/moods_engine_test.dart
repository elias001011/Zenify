import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/moods/mix_engine.dart';
import 'package:musify/services/moods/moods_preferences.dart';
import 'package:musify/services/moods/taste.dart';

Map<String, dynamic> song(
  String id, {
  String artist = 'Artist',
  String? title,
  int duration = 200,
}) => {
  'ytid': id,
  'title': title ?? id,
  'artist': artist,
  'duration': duration,
};

void main() {
  test('rain, hour-long mixes and live streams are not songs', () {
    expect(looksLikeSong(song('a', title: 'Garota de Ipanema')), isTrue);
    expect(
      looksLikeSong(song('b', title: 'Barulho de chuva para dormir')),
      isFalse,
    );
    expect(looksLikeSong(song('c', title: 'Lofi beats 3 hours')), isFalse);
    expect(
      looksLikeSong(song('d', title: 'Rain Sounds', artist: 'Nature')),
      isFalse,
    );
    expect(looksLikeSong(song('e', duration: 3600)), isFalse);
    expect(looksLikeSong({...song('f'), 'isLive': true}), isFalse);
    // A word inside another one is not a match.
    expect(looksLikeSong(song('g', title: 'Brainstorm')), isTrue);
  });

  test('artists compare across credits and spellings', () {
    expect(artistKey('Seu Jorge & Ana Carolina'), artistKey('seu jorge'));
    expect(artistKey('Anitta feat. Cardi B'), artistKey('ANITTA'));
    expect(artistKey('Djavan'), isNot(artistKey('Caetano Veloso')));
  });

  test('taste leans on recent listening and leaves noise and blocks out', () {
    final now = DateTime(2026, 10, 30);
    final taste = Taste.of(
      now: now,
      recap: [
        {
          'a': {
            ...song('a', artist: 'Djavan'),
            'seconds': 3000,
            'lastPlayed': '2026-10-29T10:00:00',
          },
          'rain': {
            ...song('rain', title: 'Chuva forte para dormir'),
            'seconds': 90000,
          },
        },
        {
          'old': {...song('old', artist: 'Legião Urbana'), 'seconds': 3000},
        },
      ],
      liked: [song('liked', artist: 'Marisa Monte')],
      recentlyPlayed: [song('blocked', artist: 'Blocked Band')],
      blockedArtists: {artistKey('Blocked Band')},
    );

    expect(taste.seeds.first.song['ytid'], 'a');
    final ids = taste.seeds.map((s) => s.song['ytid']).toList();
    expect(ids, isNot(contains('rain')));
    expect(ids, isNot(contains('blocked')));
    // Last month's favourite counts, half as much.
    expect(
      taste.seeds.firstWhere((s) => s.song['ytid'] == 'old').weight,
      lessThan(taste.seeds.first.weight),
    );
    // Heard counts as known even when it is no seed.
    expect(taste.known, containsAll(['a', 'rain', 'blocked', 'liked']));
    expect(taste.artists[artistKey('Djavan')], 1);
  });

  Map<String, ({Map song, double score})> scored(Iterable<Map> songs) => {
    for (final (i, s) in songs.indexed)
      s['ytid'].toString(): (song: s, score: 100.0 - i),
  };

  test('a queue keeps the new share the discovery asks for', () {
    final taste = Taste.of(
      liked: [for (var i = 0; i < 30; i++) song('k$i', artist: 'Known $i')],
    );
    final candidates = scored([
      for (var i = 0; i < 30; i++) song('k$i', artist: 'Known $i'),
      for (var i = 0; i < 30; i++) song('n$i', artist: 'New $i'),
    ]);

    int newIn(List<Map> queue) =>
        queue.where((s) => s['ytid'].toString().startsWith('n')).length;
    for (final (discovery, share) in [
      (Discovery.familiar, 0.4),
      (Discovery.balanced, 0.65),
      (Discovery.adventurous, 0.85),
    ]) {
      final queue = assembleQueue(
        taste: taste,
        scored: candidates,
        discovery: discovery,
        length: 20,
        random: Random(1),
      );
      expect(queue, hasLength(20));
      expect(newIn(queue), closeTo(20 * share, 1.5));
    }
    final onlyNew = assembleQueue(
      taste: taste,
      scored: candidates,
      discovery: Discovery.onlyNew,
      length: 20,
      random: Random(1),
    );
    expect(newIn(onlyNew), 20);
  });

  test('an artist plays a few times at most and never twice in a row', () {
    final queue = assembleQueue(
      taste: const Taste(),
      scored: scored([
        for (var i = 0; i < 10; i++) song('a$i', artist: 'Same'),
        for (var i = 0; i < 10; i++) song('b$i', artist: 'Other $i'),
      ]),
      length: 12,
      random: Random(2),
    );
    expect(queue.where((s) => s['artist'] == 'Same'), hasLength(3));
    for (var i = 1; i < queue.length; i++) {
      expect(queue[i]['artist'], isNot(queue[i - 1]['artist']));
    }
  });

  test('excluded artists never make it into a queue', () {
    final queue = assembleQueue(
      taste: const Taste(),
      scored: scored([song('x', artist: 'Left Out'), song('y')]),
      excludedArtists: {artistKey('Left Out')},
      random: Random(3),
    );
    expect(queue.map((s) => s['ytid']), ['y']);
  });

  test('radios score songs near the top of strong and shared radios', () {
    final taste = Taste.of(liked: [song('seed1'), song('seed2')]);
    final scores = scoreRadios(
      taste: taste,
      radios: {
        'seed1': [song('seed1'), song('both'), song('only1')],
        'seed2': [song('seed2'), song('both'), song('long', duration: 4000)],
      },
      seedWeights: {'seed1': 1, 'seed2': 0.5},
    );
    expect(scores['both']!.score, greaterThan(scores['only1']!.score));
    expect(scores, isNot(contains('long')));
  });

  test('a library without tuning reads as the defaults', () {
    // As in a backup from Musify, which has none of it.
    expect(MoodsTuning.fromStorage(null).isDefault, isTrue);
    expect(MoodsTuning.fromStorage('broken').isDefault, isTrue);
    final tuning = MoodsTuning.fromStorage({
      'excludedGenres': ['Jazz'],
      'blockedArtists': ['x'],
      'discovery': 'adventurous',
      'unknown': 1,
    });
    expect(tuning.excludedGenres, {'Jazz'});
    expect(tuning.discovery, Discovery.adventurous);
    expect(
      MoodsTuning.fromStorage(tuning.toStorage()).toStorage(),
      tuning.toStorage(),
    );
  });
}
