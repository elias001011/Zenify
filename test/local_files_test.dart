import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/local_files_service.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('zenify_local_files');
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

  test('only audio files are added, once each, under a local id', () async {
    final added = await addLocalFiles([
      '/music/a.mp3',
      '/music/notes.txt',
      '/music/a.mp3',
      '/music/B.FLAC',
    ]);

    expect(added, 2);
    expect(localFiles.value.map((f) => f['title']), ['a', 'B']);
    for (final file in localFiles.value) {
      expect(isLocalSong(file), isTrue);
      expect(file['ytid'].toString(), startsWith(localSongPrefix));
    }
    expect(await addLocalFiles(['/music/a.mp3']), 0);
    // Kept on the device only: not in the library's backed-up box.
    expect((Hive.box('userNoBackup').get('localFiles') as List).length, 2);
  });

  test('removing takes the file out of the list, not off the device', () async {
    await addLocalFiles(['/music/a.mp3', '/music/b.mp3']);
    final id = localFiles.value.first['ytid'].toString();

    await removeLocalFile(id);

    expect(localFiles.value.map((f) => f['title']), ['b']);
  });

  test('a local file never becomes recently played', () async {
    await addLocalFiles(['/music/a.mp3']);
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
