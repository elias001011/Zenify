// One device of the check of the headless peer (tools/sync_peer): the app's
// own sync code, as in a real device, pairs with the peer found on the
// network and syncs with it. Started by tools/sync_peer/verify.sh, which
// gives the PIN read from the peer.
//
//   MUSIFY_HEADLESS_ROLE   a: has a liked song and sends it; b: starts empty
//   MUSIFY_HEADLESS_PIN_FILE  a file that holds the PIN the peer shows, read
//                          when the device asks to pair
//   MUSIFY_HEADLESS_DATA   a folder to keep this device in
//   MUSIFY_HEADLESS_NAME   the peer's name

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:musify/services/local_sync_service.dart';

void main() {
  final env = Platform.environment;
  final role = env['MUSIFY_HEADLESS_ROLE'];
  test(
    'device syncs with the headless peer',
    () async {
      final directory = Directory(env['MUSIFY_HEADLESS_DATA']!);
      await directory.create(recursive: true);
      Hive.init(directory.path);
      for (final name in ['user', 'userNoBackup', 'settings', 'cache']) {
        await Hive.openBox(name);
      }
      await Hive.box('settings').put('localSyncAutomatic', false);
      if (role == 'a' && Hive.box('user').get('likedSongs') == null) {
        await Hive.box('user').put('likedSongs', [
          {
            'ytid': 'dQw4w9WgXcQ',
            'title': 'Never Gonna Give You Up',
            'artist': 'Rick Astley',
          },
        ]);
      }

      final service = LocalSyncService.forTesting();
      await service.initialise();
      await service.startServer();
      addTearDown(() async {
        await service.dispose();
        await Hive.close();
      });

      final found = await service.discoverDevices();
      final peer = found.firstWhere(
        (d) => d.name == (env['MUSIFY_HEADLESS_NAME'] ?? 'Zenify Sync Server'),
      );
      stdout.writeln('Found ${peer.name} at ${peer.ip}:${peer.port}');

      final pinFile = File(env['MUSIFY_HEADLESS_PIN_FILE'] ?? '');
      final timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (service.state.value.status == LocalSyncStatus.waitingForPin &&
            pinFile.existsSync()) {
          service.submitPin(pinFile.readAsStringSync().trim());
        }
      });
      await service.syncWith(peer);
      timer.cancel();

      expect(service.state.value.status, LocalSyncStatus.success);
      final liked = Hive.box('user').get('likedSongs') as List?;
      expect(liked?.map((s) => s['ytid']), contains('dQw4w9WgXcQ'));
      stdout.writeln('Device $role synced: ${liked?.length} liked song(s)');
    },
    skip: role == null ? 'Run by tools/sync_peer/verify.sh' : null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
