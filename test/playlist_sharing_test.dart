import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/playlist_sharing.dart';

void main() {
  Map playlist(String image) => {
    'title': 'Mine',
    'image': image,
    'list': [
      for (var i = 0; i < 100; i++)
        {'ytid': 'abcdefghi${i.toString().padLeft(2, '0')}', 'title': 'T$i'},
    ],
  };

  test('a picked cover does not go into the link', () {
    final picked = base64.encode(List.filled(200000, 7));
    final shared = PlaylistSharingService.encodePlaylist(playlist(picked));
    final plain = PlaylistSharingService.encodePlaylist(playlist(''));
    expect(shared.length, plain.length);
    expect(shared.length, lessThan(3000));
  });

  test('a cover address is kept, and the songs come as ids', () {
    final compact = PlaylistSharingService.createCompactPlaylist(
      playlist('https://i.ytimg.com/vi/x/hq.jpg'),
    );
    expect(compact['image'], 'https://i.ytimg.com/vi/x/hq.jpg');
    expect(compact['list'], hasLength(100));
    expect(compact['list'].first, 'abcdefghi00');
    expect(compact['source'], 'user-created');
  });
}
