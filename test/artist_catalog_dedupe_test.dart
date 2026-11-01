import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/artist_service.dart';

void main() {
  Map<String, dynamic> song(String id, String title, String artist) => {
    'ytid': id,
    'title': title,
    'artist': artist,
  };

  test('songs with titles in other scripts stay apart', () {
    final kept = dedupeArtistCatalogSongs([
      song('a1', '夜に駆ける', 'YOASOBI'),
      song('a2', 'アイドル', 'YOASOBI'),
      song('a3', 'Всё хорошо', 'Artist'),
      song('a4', 'Другая песня', 'Artist'),
    ]);

    expect(kept.map((s) => s['ytid']), ['a1', 'a2', 'a3', 'a4']);
  });

  test('accents keep different songs apart, punctuation does not', () {
    final kept = dedupeArtistCatalogSongs([
      song('b1', 'Coração', 'Artist'),
      song('b2', 'Cora', 'Artist'),
      song('b3', 'Coração!', 'Artist'),
    ]);

    expect(kept.map((s) => s['ytid']), ['b1', 'b2']);
  });

  test('only whole words make an artist look unofficial', () {
    for (final name in ['Fancy', 'Fantasia', 'Recovery', 'Discovery']) {
      expect(looksUnofficialArtistName(name), isFalse, reason: name);
    }
    for (final name in ['Queen Fans', 'Song Cover Channel', 'Lyrics Hub']) {
      expect(looksUnofficialArtistName(name), isTrue, reason: name);
    }
  });
}
