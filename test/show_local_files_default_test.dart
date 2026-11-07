import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:musify/services/local_files_service.dart';
import 'package:musify/services/settings_manager.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('zenify_show_local');
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
    await Hive.box('settings').delete('showLocalFiles');
  });

  test('stays off for a library without local files', () {
    reloadSettingsFromStorage();

    expect(showLocalFiles.value, isFalse);
  });

  test('stays on for an update that already has local files', () {
    localFiles.value = [
      {'ytid': 'local:a', 'title': 'a', 'audioPath': '/a.mp3'},
    ];

    reloadSettingsFromStorage();

    expect(showLocalFiles.value, isTrue);
  });

  test('a choice made in Settings wins over the files', () async {
    localFiles.value = [
      {'ytid': 'local:a', 'title': 'a', 'audioPath': '/a.mp3'},
    ];
    await Hive.box('settings').put('showLocalFiles', false);

    reloadSettingsFromStorage();

    expect(showLocalFiles.value, isFalse);
  });
}
