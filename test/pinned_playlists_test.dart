import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/playlists_manager.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('zenify_pins');
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });
  // Writes started under the test clock may still be pending; the process
  // ends right after, so the boxes are left open.
  tearDownAll(
    () => directory.delete(recursive: true).catchError((_) => directory),
  );

  testWidgets('a pin whose playlist is gone does not take a place', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    userCustomPlaylists.value = [
      for (var i = 1; i <= 5; i++)
        {'ytid': 'p$i', 'title': 'Playlist $i', 'list': <Map>[]},
    ];
    // Four pins that show and one left behind by a deleted playlist.
    pinnedPlaylistIds.value = ['deleted', 'p1', 'p2', 'p3', 'p4'];

    expect(togglePinnedPlaylist('p5', context), isTrue);
    expect(pinnedPlaylistIds.value, ['p1', 'p2', 'p3', 'p4', 'p5']);
    expect(pinnedPlaylistIds.value, hasLength(pinnedPlaylistsLimit));
    // The sixth is turned down; the five stay.
    userCustomPlaylists.value = [
      ...userCustomPlaylists.value,
      {'ytid': 'p6', 'title': 'Playlist 6', 'list': <Map>[]},
    ];
    expect(togglePinnedPlaylist('p6', context), isFalse);
    expect(pinnedPlaylistIds.value, hasLength(pinnedPlaylistsLimit));
  });
}
