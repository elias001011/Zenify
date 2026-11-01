import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/io_service.dart';
import 'package:musify/services/local_files_service.dart';

void main() {
  late Directory directory;
  late Directory music;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('zenify_local_files');
    music = Directory('${directory.path}/music')..createSync();
    applicationDirPath = directory.path;
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });
  tearDownAll(
    () => directory.delete(recursive: true).catchError((_) => directory),
  );

  setUp(() async {
    localFiles.value = [];
    await Hive.box('userNoBackup').delete('localFiles');
    userRecentlyPlayed.value = [];
  });

  String makeFile(String name, String content) {
    final file = File('${music.path}/$name')..writeAsStringSync(content);
    return file.path;
  }

  test('only audio files are added, once each, under a local id', () async {
    final a = makeFile('a.mp3', 'first song');
    final notes = makeFile('notes.txt', 'not audio');
    final b = makeFile('B.FLAC', 'second song');

    final added = await addLocalFiles([a, notes, a, b]);

    expect(added, 2);
    expect(localFiles.value.map((f) => f['title']), ['a', 'B']);
    for (final file in localFiles.value) {
      expect(isLocalSong(file), isTrue);
      expect(file['ytid'].toString(), startsWith(localSongPrefix));
    }
    expect(await addLocalFiles([a]), 0);
    // Kept on the device only: not in the library's backed-up box.
    expect((Hive.box('userNoBackup').get('localFiles') as List).length, 2);
  });

  test('the picked file is kept, and its copy is never the original', () async {
    final original = makeFile('keep.mp3', 'kept audio');
    await addLocalFiles([original]);
    final file = localFiles.value.single;
    final copy = file['audioPath'].toString();

    expect(copy, isNot(original));
    expect(copy, startsWith('${directory.path}/$localFilesDirName/'));
    expect(File(copy).readAsStringSync(), 'kept audio');
  });

  test(
    'removing takes the file out of the list and deletes only its copy',
    () async {
      final a = makeFile('gone.mp3', 'to remove');
      await addLocalFiles([a, makeFile('stays.mp3', 'stays')]);
      final removed = localFiles.value.first;
      final copy = removed['audioPath'].toString();

      await removeLocalFile(removed['ytid'].toString());

      expect(localFiles.value.map((f) => f['title']), ['stays']);
      expect(File(copy).existsSync(), isFalse);
      expect(File(a).existsSync(), isTrue);
    },
  );

  test('entries from an older build move their copy off the cache', () async {
    final original = makeFile('old.mp3', 'old audio');
    localFiles.value = [
      {
        'ytid': 'local:oldpathid',
        'title': 'old',
        'artist': '',
        'audioPath': original,
      },
    ];

    await keepLocalFileCopies();

    final file = localFiles.value.single;
    expect(file['audioPath'].toString(), startsWith(directory.path));
    expect(file['audioPath'].toString(), isNot(original));
    expect(isLocalSong(file), isTrue);
    expect(File(file['audioPath'].toString()).readAsStringSync(), 'old audio');
  });

  test(
    'the same song under another extension is one entry and one copy',
    () async {
      final mp3 = makeFile('same.mp3', 'identical audio');
      final flac = makeFile('same.flac', 'identical audio');

      expect(await addLocalFiles([mp3, flac]), 1);

      final digest = sha1.convert(utf8.encode('identical audio')).toString();
      final storage = Directory('${directory.path}/$localFilesDirName');
      final copies = storage
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .where((name) => name.startsWith(digest));
      expect(localFiles.value, hasLength(1));
      expect(copies, ['$digest.mp3']);
    },
  );

  test(
    'a removal made while the old entries are moved is not undone',
    () async {
      final keep = makeFile('race-keep.mp3', 'keep me');
      final gone = makeFile('race-gone.mp3', 'remove me');
      localFiles.value = [
        {
          'ytid': 'local:racekeep',
          'title': 'keep',
          'artist': '',
          'audioPath': keep,
        },
        {
          'ytid': 'local:racegone',
          'title': 'gone',
          'artist': '',
          'audioPath': gone,
        },
      ];

      final migration = keepLocalFileCopies();
      final removal = removeLocalFile('local:racegone');
      await Future.wait([migration, removal]);

      expect(localFiles.value.map((f) => f['title']), ['keep']);
      expect(
        File(localFiles.value.single['audioPath'].toString())
            .readAsStringSync(),
        'keep me',
      );
    },
  );

  test('a local file never becomes recently played', () async {
    await addLocalFiles([makeFile('recent.mp3', 'recent')]);
    final file = localFiles.value.single;

    await updateRecentlyPlayed(file['ytid'], songFallback: file);

    expect(userRecentlyPlayed.value, isEmpty);
  });

  test('ids of online songs are not local', () {
    expect(isLocalSongId('dQw4w9WgXcQ'), isFalse);
    expect(isLocalSongId(null), isFalse);
    expect(isLocalSong({'ytid': 'local:x'}), isTrue);
    expect(isLocalSong(null), isFalse);
  });
}
