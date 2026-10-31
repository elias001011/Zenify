import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/music_radio.dart';
import 'package:musify/services/settings_manager.dart';

Map<String, dynamic> song(String id) => {'ytid': id, 'title': id};

void main() {
  var radioCalls = <String>[];
  late Map<String, List<Map>> radios;

  setUpAll(() async {
    final directory = await Directory.systemTemp.createTemp('zenify_radio');
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });

  setUp(() {
    offlineMode.value = false;
    radioCalls = [];
    radios = {};
    forgetRadios();
    radioOf = (id) async {
      radioCalls.add(id);
      return radios[id] ?? <Map>[];
    };
    relatedTo = (id, {Set<String> excludedYtIds = const {}}) async =>
        song('related-of-$id');
    fallbackRecommendations = (id, songs) async => [song('fallback')];
  });

  group('the automatic picker', () {
    test('follows one radio while it has songs left', () async {
      radios['a'] = [song('b'), song('c'), song('d')];
      expect((await pickNextSong('a', excludedYtIds: {'a'}))!['ytid'], 'b');
      expect(
        (await pickNextSong('b', excludedYtIds: {'a', 'b'}))!['ytid'],
        'c',
      );
      expect(
        (await pickNextSong('c', excludedYtIds: {'a', 'b', 'c'}))!['ytid'],
        'd',
      );
      expect(radioCalls, ['a']);
    });

    test('asks again from the current song when the radio runs out', () async {
      radios['a'] = [song('b')];
      radios['b'] = [song('x')];
      await pickNextSong('a', excludedYtIds: {'a'});
      final next = await pickNextSong('b', excludedYtIds: {'a', 'b'});
      expect(next!['ytid'], 'x');
      expect(radioCalls, ['a', 'b']);
    });

    test('skips what is already in the queue', () async {
      radios['a'] = [song('b'), song('c')];
      final next = await pickNextSong('a', excludedYtIds: {'a', 'b'});
      expect(next!['ytid'], 'c');
    });

    test('falls back to the related videos when the radio has none', () async {
      // A seed that is no song, as rain sounds from YouTube, has no radio.
      expect((await pickNextSong('rain'))!['ytid'], 'related-of-rain');
      radios['a'] = [song('b')];
      expect(
        (await pickNextSong('a', excludedYtIds: {'a', 'b'}))!['ytid'],
        'related-of-a',
      );
    });

    test('never asks for a radio offline', () async {
      offlineMode.value = true;
      radios['a'] = [song('b')];
      expect((await pickNextSong('a'))!['ytid'], 'related-of-a');
      expect(radioCalls, isEmpty);
    });
  });

  group('recommendations for a playlist', () {
    test('merge the radios of its songs and leave out what it has', () async {
      final playlist = [song('a'), song('b')];
      radios['a'] = [song('x'), song('b'), song('y')];
      radios['b'] = [song('y'), song('z')];
      final picks = await getPlaylistRecommendations('p', playlist);
      final ids = picks.map((s) => s['ytid']).toList();
      expect(ids, isNot(contains('a')));
      expect(ids, isNot(contains('b')));
      expect(ids.toSet(), {'x', 'y', 'z'});
    });

    test('fall back to the related videos when no radio has songs', () async {
      final picks = await getPlaylistRecommendations('q', [song('a')]);
      expect(picks.single['ytid'], 'fallback');
    });

    test('are kept for the next time the page opens', () async {
      radios['a'] = [song('x')];
      await getPlaylistRecommendations('r', [song('a')]);
      radioCalls.clear();
      final again = await getPlaylistRecommendations('r', [song('a')]);
      expect(again.single['ytid'], 'x');
      expect(radioCalls, isEmpty);
    });
  });
}
