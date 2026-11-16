import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/moods/moods_service.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/settings_manager.dart' show moodsEnabled;

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
    expect(pinnedPlaylistIds.value, ['deleted', 'p1', 'p2', 'p3', 'p4', 'p5']);
    expect(
      resolvePinnedPlaylists(pinnedPlaylistIds.value),
      hasLength(pinnedPlaylistsLimit),
    );
    // The sixth is turned down; the five stay.
    userCustomPlaylists.value = [
      ...userCustomPlaylists.value,
      {'ytid': 'p6', 'title': 'Playlist 6', 'list': <Map>[]},
    ];
    expect(togglePinnedPlaylist('p6', context), isFalse);
    expect(pinnedPlaylistIds.value, isNot(contains('p6')));
    expect(
      resolvePinnedPlaylists(pinnedPlaylistIds.value),
      hasLength(pinnedPlaylistsLimit),
    );
  });

  testWidgets('a pin whose playlist has not loaded yet is kept', (
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
      for (var i = 1; i <= 2; i++)
        {'ytid': 'p$i', 'title': 'Playlist $i', 'list': <Map>[]},
    ];
    onlinePlaylists.value = [];
    // A YouTube playlist the user added: offline it is not in memory yet.
    pinnedPlaylistIds.value = ['PLyoutube', 'p1'];

    expect(togglePinnedPlaylist('p2', context), isTrue);
    expect(pinnedPlaylistIds.value, ['PLyoutube', 'p1', 'p2']);
    expect(togglePinnedPlaylist('p1', context), isFalse);
    expect(pinnedPlaylistIds.value, ['PLyoutube', 'p2']);

    onlinePlaylists.value = [
      {'ytid': 'PLyoutube', 'title': 'Mix', 'list': <Map>[]},
    ];
    expect(
      resolvePinnedPlaylists(pinnedPlaylistIds.value).map((p) => p['ytid']),
      ['PLyoutube', 'p2'],
    );
  });

  testWidgets('a pinned Zenify playlist is kept and listed', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    userCustomPlaylists.value = [];
    pinnedPlaylistIds.value = [];

    expect(togglePinnedPlaylist('zenify:daily', context), isTrue);
    // Another pin later must not sweep it away as a playlist that is gone.
    userCustomPlaylists.value = [
      {'ytid': 'p1', 'title': 'Playlist 1', 'list': <Map>[]},
    ];
    expect(togglePinnedPlaylist('p1', context), isTrue);

    expect(pinnedPlaylistIds.value, ['zenify:daily', 'p1']);
    final listed = resolvePinnedPlaylists(pinnedPlaylistIds.value);
    expect(listed.map((p) => p['ytid']), ['zenify:daily', 'p1']);
    expect(MoodsService.isZenifyPlaylist('zenify:daily'), isTrue);
  });

  testWidgets('a pin on a Zenify playlist is not counted with the Moods off', (
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
    userCustomPlaylists.value = [];
    pinnedPlaylistIds.value = [];
    final before = moodsEnabled.value;
    addTearDown(() => moodsEnabled.value = before);

    moodsEnabled.value = true;
    expect(togglePinnedPlaylist('zenify:daily', context), isTrue);
    moodsEnabled.value = false;
    // Hidden with the Moods, so it must not take one of the places.
    expect(resolvePinnedPlaylists(pinnedPlaylistIds.value), isEmpty);
  });
}
