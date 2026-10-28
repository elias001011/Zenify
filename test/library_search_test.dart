import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/library_search.dart';
import 'package:musify/services/playlists_manager.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('musify_library_search');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box);
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Map song(String id, String title, String artist) => {
    'ytid': id,
    'title': title,
    'artist': artist,
  };

  test('finds songs by title or artist once, and playlists by title', () {
    final shared = song('s1', 'Blue Hour', 'Calm');
    userLikedSongsList.value = [shared, song('s2', 'Red', 'Loud')];
    userOfflineSongs.value = [shared];
    userCustomPlaylists.value = [
      {
        'ytid': 'p1',
        'title': 'Blue mornings',
        'source': 'user-created',
        'list': [song('s3', 'Sunrise', 'Blue Band')],
      },
    ];

    final result = searchLibrary('blue');

    expect(result.songs.map((s) => s['ytid']), unorderedEquals(['s1', 's3']));
    expect(result.playlists.single['ytid'], 'p1');
  });

  test('offline keeps to downloaded songs', () {
    userLikedSongsList.value = [song('s2', 'Blue Red', 'Loud')];
    userOfflineSongs.value = [song('s1', 'Blue Hour', 'Calm')];

    final result = searchLibrary('blue', offlineOnly: true);

    expect(result.songs.map((s) => s['ytid']), ['s1']);
  });

  test('folder songs remain searchable and online playlists stay out of offline results', () {
    userCustomPlaylists.value = [];
    userPlaylistFolders.value = [
      {
        'id': 'folder',
        'name': 'Folder',
        'playlists': [
          {
            'ytid': 'folder-playlist',
            'title': 'Blue folder',
            'source': 'user-created',
            'list': [song('folder-song', 'Blue folder song', 'Artist')],
          },
        ],
      },
    ];
    expect(
      searchLibrary('blue').songs.map((s) => s['ytid']),
      contains('folder-song'),
    );
    expect(searchLibrary('blue', offlineOnly: true).playlists, isEmpty);
  });

  test('an empty query matches nothing', () {
    expect(searchLibrary('  ').songs, isEmpty);
  });
}
