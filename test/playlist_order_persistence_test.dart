import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/data_manager.dart';

import 'local_sync/fixtures.dart';

void main() {
  test(
    'sync keeps manual order in root and nested playlists, conflicts converge',
    () {
      final initial = <String, dynamic>{
        'customPlaylists': [
          playlist('root', ['c', 'a', 'b']),
        ],
        'playlistFolders': [
          {
            'id': 'folder',
            'name': 'Folder',
            'playlists': [
              playlist('nested', ['z', 'x', 'y']),
            ],
          },
        ],
      };
      final a = document(initial), b = document(initial);
      final baseline = a.materialize();
      final edited = <String, dynamic>{
        ...baseline,
        'customPlaylists': [
          playlist('root', ['b', 'c', 'a']),
        ],
        'playlistFolders': [
          {
            'id': 'folder',
            'name': 'Folder',
            'playlists': [
              playlist('nested', ['y', 'z', 'x']),
            ],
          },
        ],
      };
      a.capture(edited, baseline, 'a');
      b.join(a);
      expect(
        b
            .materialize()['customPlaylists'][0]['list']
            .map((s) => s['ytid'])
            .toList(),
        ['b', 'c', 'a'],
      );
      expect(
        b
            .materialize()['playlistFolders'][0]['playlists'][0]['list']
            .map((s) => s['ytid'])
            .toList(),
        ['y', 'z', 'x'],
      );
      final c = document(initial), d = document(initial);
      c.capture(
        {
          ...baseline,
          'customPlaylists': [
            playlist('root', ['b', 'c', 'a']),
          ],
        },
        baseline,
        'c',
      );
      d.capture(
        {
          ...baseline,
          'customPlaylists': [
            playlist('root', ['a', 'b', 'c']),
          ],
        },
        baseline,
        'd',
      );
      c.join(d);
      d.join(c);
      final first = c
          .materialize()['customPlaylists'][0]['list']
          .map((s) => s['ytid'])
          .toList();
      final second = d
          .materialize()['customPlaylists'][0]['list']
          .map((s) => s['ytid'])
          .toList();
      expect(first, second);
      expect(first, ['a', 'b', 'c']);
    },
  );

  test(
    'validated Hive backup roundtrip preserves root and nested song order',
    () async {
      final dir = await Directory.systemTemp.createTemp('zenify_backup_order');
      addTearDown(() async {
        await Hive.close();
        await dir.delete(recursive: true);
      });
      Hive.init(dir.path);
      final user = await Hive.openBox('user');
      await user.put('customPlaylists', [
        playlist('root', ['c', 'a', 'b']),
      ]);
      await user.put('playlistFolders', [
        {
          'id': 'folder',
          'name': 'Folder',
          'playlists': [
            playlist('nested', ['z', 'x', 'y']),
          ],
        },
      ]);
      await user.flush();
      final bytes = await File(user.path!).readAsBytes();
      await validateHiveBackup('user', bytes);
      final restored = await Hive.openBox('roundtrip', bytes: bytes);
      expect(
        restored
            .get('customPlaylists')[0]['list']
            .map((s) => s['ytid'])
            .toList(),
        ['c', 'a', 'b'],
      );
      expect(
        restored
            .get('playlistFolders')[0]['playlists'][0]['list']
            .map((s) => s['ytid'])
            .toList(),
        ['z', 'x', 'y'],
      );
    },
  );
}
