import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/install_config_service.dart';
import 'package:musify/utilities/startup_support.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('zenify_migration');
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  Future<Directory> library(String path, String title) async {
    final dir = await Directory('${root.path}/$path').create(recursive: true);
    Hive.init(dir.path);
    final user = await Hive.openBox('user');
    await user.put('likedSongs', [
      {'ytid': title, 'title': title},
    ]);
    await user.put('offlineSongs', [
      {'ytid': title, 'audioPath': '/Musify/tracks/$title.m4a'},
    ]);
    final settings = await Hive.openBox('settings');
    await settings.put('themeIndex', 2);
    await Hive.close();
    return dir;
  }

  test(
    'migrates real Musify boxes and prefers modern support over old Documents',
    () async {
      final modern = await library('com.gokadzev.musify', 'Current');
      final old = await library('Documents', 'Outdated');
      final target = Directory('${root.path}/Zenify');
      final report = await migrateLegacyDesktopData(
        target: target,
        sources: [modern, old],
      );
      expect(report.failed, isEmpty);
      Hive.init(target.path);
      final user = await Hive.openBox('user', crashRecovery: false);
      expect(user.get('likedSongs').single['ytid'], 'Current');
      expect(
        user.get('offlineSongs').single['audioPath'],
        '/Musify/tracks/Current.m4a',
      );
      expect(
        (await Hive.openBox(
          'settings',
          crashRecovery: false,
        )).get('themeIndex'),
        2,
      );
      expect(File('${modern.path}/user.hive').existsSync(), isTrue);
    },
  );

  test('resumes interruption between box promotions without emptying missing boxes', () async {
    final source = await library('old', 'Music');
    final target = await Directory('${root.path}/new').create();
    final stage = await Directory('${target.path}/.hive-migration').create();
    await File('${source.path}/user.hive').copy('${target.path}/user.hive');
    await File('${source.path}/settings.hive')
        .copy('${stage.path}/settings.hive');
    await File('${stage.path}/pending.json')
        .writeAsString(jsonEncode(['user.hive', 'settings.hive']));
    final report = await copyHiveBoxes(from: source, to: target);
    expect(report.copied, containsAll(['user.hive', 'settings.hive']));
    Hive.init(target.path);
    expect(
      (await Hive.openBox(
        'user',
        crashRecovery: false,
      )).get('likedSongs').single['ytid'],
      'Music',
    );
    expect(
      (await Hive.openBox('settings', crashRecovery: false)).get('themeIndex'),
      2,
    );
    expect(stage.existsSync(), isFalse);
  });

  test(
    'changing the installer location copies the previous custom library',
    () async {
      final defaultDir = await library('default', 'Old default');
      final previous = await library('custom', 'Current library');
      final target = '${root.path}/new-custom';
      final path = await InstallConfig(
        dataDir: target,
        previousDataDir: previous.path,
      ).resolveDataDir(defaultDir.path);
      Hive.init(path);
      expect(
        (await Hive.openBox('user')).get('likedSongs').single['ytid'],
        'Current library',
      );
    },
  );

  test('an incomplete journal aborts startup instead of falling back to a writable source', () async {
    final source = await library('source', 'Current');
    final target = await Directory('${root.path}/target/.hive-migration')
        .create(recursive: true);
    await File('${target.path}/pending.json').writeAsString('["user.hive"]');
    await expectLater(
      InstallConfig(dataDir: target.parent.path).resolveDataDir(source.path),
      throwsA(isA<HiveMigrationPending>()),
    );
    expect(File('${source.path}/user.hive').existsSync(), isTrue);
  });

  test(
    'finds legacy platform paths without using the new product identity',
    () {
      expect(
        legacyMusifyDirectories('/data/Zenify', windows: false).first.path,
        '/data/com.gokadzev.musify',
      );
      expect(
        legacyMusifyDirectories(
          'unused',
          windows: true,
          environment: {'APPDATA': 'C:/Users/Me/AppData/Roaming'},
        ).map((d) => d.path),
        contains('C:/Users/Me/AppData/Roaming/com.gokadzev/Musify'),
      );
    },
  );
}
