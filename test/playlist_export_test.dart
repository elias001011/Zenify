import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/playlist_export_service.dart';
import 'package:musify/services/playlists_manager.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('zenify_export');
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('the CSV has Song and Artist columns and quotes what needs it', () {
    final csv = playlistCsv([
      {'ytid': 'abcdefghijk', 'title': 'Hello, "World"', 'artist': 'A\nB'},
      {'ytid': '', 'title': 'No id', 'artist': 'C', 'duration': 90},
      {'title': '   ', 'artist': 'skipped'},
    ]);

    expect(csv.startsWith('﻿Song,Artist,Duration (ms),YouTube ID,'), isTrue);
    expect(
      csv,
      contains(
        '"Hello, ""World""","A\nB",,abcdefghijk,'
        'https://music.youtube.com/watch?v=abcdefghijk\r\n',
      ),
    );
    expect(csv, contains('No id,C,90000,,\r\n'));
    expect(csv, isNot(contains('skipped')));
  });

  test('file names are safe and never repeat', () {
    final taken = <String>{};

    expect(csvFileName('Road trip', taken), 'Road trip.csv');
    expect(csvFileName('road trip', taken), 'road trip (2).csv');
    expect(csvFileName('a/b:c*?"<>|', taken), 'a_b_c______.csv');
    expect(csvFileName('  ...', taken), 'playlist.csv');
    expect(csvFileName('x' * 200, taken).length, 84);
  });

  test('a title that looks like a formula is shown, not run', () {
    final csv = playlistCsv([
      {'ytid': '-abcdefghij', 'title': '=HYPERLINK("x")', 'artist': '+1'},
    ]);

    expect(csv, contains('"\'=HYPERLINK(""x"")",\'+1,,-abcdefghij,'));
  });

  test('names avoid Windows devices and files already in the folder', () {
    final taken = <String>{};

    expect(csvFileName('CON', taken), '_CON.csv');
    expect(
      csvFileName('Mine', taken, exists: (name) => name == 'Mine.csv'),
      'Mine (2).csv',
    );
  });

  test(
    'liked songs and custom playlists are written, the rest counted',
    () async {
      userLikedSongsList.value = [
        {'ytid': 'likedlikedl', 'title': 'Liked', 'artist': 'Me'},
      ];
      userCustomPlaylists.value = [
        {
          'ytid': 'customId-1',
          'title': 'Mine',
          'source': 'user-created',
          'list': [
            {'ytid': 'customcusto', 'title': 'Custom song', 'artist': 'You'},
          ],
        },
        {
          'ytid': 'customId-2',
          'title': 'Empty',
          'source': 'user-created',
          'list': [],
        },
      ];
      final entries = [
        (
          id: likedSongsExportId,
          title: 'Liked',
          source: ExportSource.likedSongs,
          artwork: null,
        ),
        (
          id: 'customId-1',
          title: 'Mine',
          source: ExportSource.custom,
          artwork: null,
        ),
        (
          id: 'customId-2',
          title: 'Empty',
          source: ExportSource.custom,
          artwork: null,
        ),
      ];
      final out = Directory('${directory.path}/out');

      final result = await writePlaylistCsvs(entries, out);

      expect(result.failed, 1);
      expect(
        out.listSync().map((e) => e.path.split('/').last).toList()..sort(),
        ['Liked.csv', 'Mine.csv'],
      );
      expect(
        File('${out.path}/Mine.csv').readAsStringSync(),
        contains('Custom song,You'),
      );
      // A second export leaves the first files alone.
      final again = await writePlaylistCsvs(entries.take(2), out);
      expect(again.files.map((path) => path.split('/').last).toList()..sort(), [
        'Liked (2).csv',
        'Mine (2).csv',
      ]);
    },
  );
}
