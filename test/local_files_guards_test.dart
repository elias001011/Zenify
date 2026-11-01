import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/utilities/mediaitem.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('musify_local_guards');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box);
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  const localSong = {
    'id': 'local:0123abcd',
    'ytid': 'local:0123abcd',
    'title': 'Local song',
    'artist': '',
  };

  test('a song without artwork gets no artUri, not the text "null"', () {
    final item = mapToMediaItem(localSong);

    expect(item.artUri, isNull);
    expect(mediaItemToMap(item)['highResImage'], isNull);
  });

  test('a song with artwork keeps its artUri', () {
    final item = mapToMediaItem({
      ...localSong,
      'highResImage': 'https://example.com/cover.jpg',
    });

    expect(item.artUri, Uri.parse('https://example.com/cover.jpg'));
  });

  test('a local id never reaches the stream lookup', () async {
    expect(await fetchSongStreamUrl('local:0123abcd', false), isNull);
  });

  test('a local id never reaches the song details lookup', () async {
    expect(await getSongDetails(0, 'local:0123abcd'), isEmpty);
  });
}
