import 'package:flutter_test/flutter_test.dart';
import 'package:musify/utilities/listening_stats_utils.dart';

void main() {
  Map<String, dynamic> song(String id, String artist, int seconds) => {
    'ytid': id,
    'artist': artist,
    'seconds': seconds,
    'playCount': seconds ~/ 60,
  };

  test('ranks artists by time, boosted by how many songs were heard', () {
    final artists = topListeningArtists([
      // One song on repeat: 30 minutes.
      song('a1', 'Repeat', 1800),
      // Four songs, 25 minutes in all.
      song('b1', 'Variety', 400),
      song('b2', 'Variety', 400),
      song('b3', 'Variety', 400),
      song('b4', 'Variety', 300),
      song('c1', 'Rare', 60),
    ]);

    expect(artists.map((a) => a.name), ['Variety', 'Repeat', 'Rare']);
    expect(artists.first.seconds, 1500);
    expect(artists.first.songCount, 4);
    expect(artists.first.topSong['ytid'], anyOf('b1', 'b2', 'b3'));
  });

  test('skips songs without an artist or time, and keeps the top five', () {
    final artists = topListeningArtists([
      song('x', '', 500),
      song('y', 'Silent', 0),
      for (var i = 0; i < 8; i++) song('s$i', 'Artist $i', 100 + i),
    ]);

    expect(artists, hasLength(wrappedTopArtistsLimit));
    expect(artists.first.name, 'Artist 7');
    expect(artists.map((a) => a.name), isNot(contains('Silent')));
  });
}
