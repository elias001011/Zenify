import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/library_search.dart';
import 'package:musify/services/local_files_service.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/settings_manager.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings();

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

  test(
    'enabled local files are searchable by title and artist, including offline',
    () {
      localFiles.value = [song('local:sample', 'My recording', 'Blue artist')];
      showLocalFiles.value = true;
      expect(searchLibrarySongs('recording').single['ytid'], 'local:sample');
      expect(
        searchLibrarySongs('Blue artist', offlineOnly: true).single['ytid'],
        'local:sample',
      );
      showLocalFiles.value = false;
      expect(searchLibrarySongs('recording'), isEmpty);
      localFiles.value = [];
    },
  );

  test('an empty query matches nothing', () {
    expect(searchLibrary('  ').songs, isEmpty);
  });

  test('search results put what the library holds first, as its copy', () {
    final mine = song('s1', 'Blue Hour (renamed)', 'Calm');
    final result = libraryFirst(
      [song('s2', 'Blue', 'Calm')],
      [
        song('s3', 'Blue Moon', 'Other'),
        song('s1', 'Blue Hour', 'Calm'),
        song('s2', 'Blue', 'Calm'),
      ],
      known: {'s1': mine},
    );

    expect(result.map((s) => s['ytid']), ['s2', 's1', 's3']);
    expect(result[1], same(mine));
  });

  test('the library copy borrows the length the online result has', () {
    final mine = song('s1', 'Blue Hour', 'Calm');
    final alsoMine = song('s2', 'Blue', 'Calm');
    final withLength = {...song('s3', 'Blue Moon', 'Other'), 'duration': 200};
    final result = libraryFirst(
      [alsoMine],
      [
        {...song('s2', 'Blue', 'Calm'), 'duration': 187},
        {...song('s1', 'Blue Hour', 'Calm'), 'duration': 215},
        withLength,
      ],
      known: {'s1': mine},
    );

    expect(result.map((s) => s['ytid']), ['s2', 's1', 's3']);
    expect(result[0]['duration'], 187);
    expect(result[1]['duration'], 215);
    expect(result[2], same(withLength));
    // The stored songs are not touched.
    expect(mine.containsKey('duration'), isFalse);
    expect(alsoMine.containsKey('duration'), isFalse);
  });

  test('a library copy with its own length keeps it', () {
    final mine = {...song('s1', 'Blue Hour', 'Calm'), 'duration': 100};
    final result = libraryFirst(
      [mine],
      [
        {...song('s1', 'Blue Hour', 'Calm'), 'duration': 215},
      ],
    );
    expect(result.single, same(mine));
  });
}
