import 'package:flutter_test/flutter_test.dart';
import 'package:musify/utilities/youtube_url.dart';

void main() {
  const id = 'dQw4w9WgXcQ';
  test('extracts pasted YouTube video links including share parameters', () {
    for (final url in [
      'https://www.youtube.com/watch?v=$id&list=PLtest',
      'https://music.youtube.com/watch?v=$id',
      'https://youtu.be/$id?si=share',
      'youtube.com/shorts/$id?si=share',
      'https://m.youtube.com/live/$id?t=23',
      'http://www.youtube.com/embed/$id',
    ]) {
      expect(youtubeVideoIdFromUrl(url), id, reason: url);
    }
  });
  test('keeps text searches and unrelated or invalid URLs as text', () {
    for (final query in [
      '',
      'radio music',
      'abcdefghijk',
      id,
      'https://example.com/watch?v=$id',
      'https://youtube.com.evil.com/watch?v=$id',
      'https://youtube.com/playlist?list=PLtest',
      'https://youtube.com/@artist',
      'https://youtube.com/watch?v=bad',
      'file://youtube.com/watch?v=$id',
    ]) {
      expect(youtubeVideoIdFromUrl(query), isNull, reason: query);
    }
  });
}
