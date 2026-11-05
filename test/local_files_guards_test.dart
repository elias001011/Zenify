import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/utilities/mediaitem.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings();

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

  test('the stream resolver refuses a local id itself', () {
    expect(
      resolveBestAudioStream('local:0123abcd'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('a local id never reaches the stream lookup', () async {
    expect(await fetchSongStreamUrl('local:0123abcd', false), isNull);
  });

  test('a local id never reaches the song details lookup', () async {
    expect(await getSongDetails(0, 'local:0123abcd'), isEmpty);
  });

  test('a local file is never stored as liked', () async {
    await updateSongLikeStatus('local:0123abcd', true, songData: localSong);

    expect(isSongAlreadyLiked('local:0123abcd'), isFalse);
  });
}
