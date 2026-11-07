import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:musify/services/data_manager.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('zenify_backup_test');
    Hive.init(root.path);
    final box = await Hive.openBox('user');
    await box.put('likedSongs', [
      {'ytid': 'legacy', 'title': 'Musify song'},
    ]);
    await box.flush();
  });
  tearDown(() async {
    await Hive.close();
    await root.delete(recursive: true);
  });

  test(
    'accepts a real Musify-compatible box without disturbing the live box',
    () async {
      final bytes = await File(Hive.box('user').path!).readAsBytes();
      await validateHiveBackup('user', bytes);
      expect(Hive.box('user').get('likedSongs').single['ytid'], 'legacy');
      expect(Hive.box('user').path, startsWith(root.path));
    },
  );

  test(
    'rejects truncated and random backups and preserves the live library',
    () async {
      final path = Hive.box('user').path!;
      final original = await File(path).readAsBytes();
      for (final bytes in [
        Uint8List.fromList([1, 2, 3, 4, 5]),
        Uint8List.sublistView(original, 0, original.length - 2),
      ]) {
        await expectLater(validateHiveBackup('user', bytes), throwsA(anything));
        expect(await File(path).readAsBytes(), original);
        expect(Hive.box('user').get('likedSongs').single['ytid'], 'legacy');
      }
    },
  );

  test('restores either backup file alone, or both', () {
    expect(matchBackupFiles(['user.hive']).keys, ['user']);
    expect(matchBackupFiles(['settings_2.hive']).keys, ['settings']);
    expect(matchBackupFiles(['settings.hive', 'user.hive']).keys, [
      'user',
      'settings',
    ]);
    expect(matchBackupFiles(['favourites.hive']), isEmpty);
  });
  test('a second copy saved in the same folder is still the backup', () {
    // Android names it "user (1).hive" instead of replacing the first one.
    expect(matchBackupFiles(['user (1).hive']).keys, ['user']);
    expect(matchBackupFiles(['settings (12).hive']).keys, ['settings']);
    expect(matchBackupFiles(['user (1).hive', 'settings (1).hive']).keys, [
      'user',
      'settings',
    ]);
    expect(matchBackupFiles(['username (1).hive']), isEmpty);
    expect(matchBackupFiles(['user (x).hive']), isEmpty);
  });
  test('rejects a nonempty Hive log with no remaining user entries', () async {
    final box = Hive.box('user');
    await box.delete('likedSongs');
    await box.flush();
    final bytes = await File(box.path!).readAsBytes();
    expect(bytes, isNotEmpty);
    await expectLater(validateHiveBackup('user', bytes), throwsFormatException);
  });
}
