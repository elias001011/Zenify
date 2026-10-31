import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/song_replacement.dart';

void main() {
  tearDown(() => findFallback = findOnYoutube);

  Map song(int i) => {'ytid': 'file:$i', 'title': 't$i', 'artist': 'a'};

  test('searches keep going when some find nothing', () async {
    findFallback = (song, {exclude = const {}}) async =>
        song['ytid'] == 'file:1' ? {'ytid': 'yt1'} : null;
    final result = await searchOnYoutube([song(0), song(1), song(2)]);
    expect(result.found.keys, ['file:1']);
    expect(result.notSearched, isEmpty);
  });

  test('searches that keep failing are not pressed on', () async {
    var calls = 0;
    findFallback = (song, {exclude = const {}}) async {
      calls++;
      throw const ReplacementSearchFailed();
    };
    var reported = 0;
    final result = await searchOnYoutube([
      for (var i = 0; i < 8; i++) song(i),
    ], onSearched: () => reported++);
    expect(calls, 3);
    expect(result.notSearched, hasLength(8));
    expect(reported, 8);
  });

  test('a search that works resets the failures', () async {
    var calls = 0;
    findFallback = (song, {exclude = const {}}) async {
      calls++;
      if (calls % 3 != 0) throw const ReplacementSearchFailed();
      return null;
    };
    final result = await searchOnYoutube([for (var i = 0; i < 9; i++) song(i)]);
    expect(calls, 9);
    expect(result.notSearched, hasLength(6));
  });
}
