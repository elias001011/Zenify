import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:musify/services/queue_persistence_service.dart';

import 'support/app_harness.dart';

Map song(int index) => {
  'ytid': 'song${index % 5}',
  'queueEntryId': 'entry$index',
  'title': 'Track $index',
  'duration': 180,
  'url': 'expired',
  'audioPath': '/music/$index.wav',
};

void main() {
  late QueuePersistenceService memory;
  useAppSettings(boxes: ['userNoBackup']);
  setUp(() async {
    await Hive.box('userNoBackup').clear();
    memory = QueuePersistenceService();
  });
  tearDown(() => memory.flush());

  test('a queue that could not be written is written again', () async {
    final songs = [for (var i = 0; i < 4; i++) song(i)];
    await Hive.box('userNoBackup').close();
    memory.saveQueue(songs, songs, 1);
    await memory.flush();

    await Hive.openBox('userNoBackup');
    memory.saveQueue(songs, songs, 1);
    await memory.flush();

    expect(memory.read()?.songs, hasLength(4));
  });

  test(
    'restores duplicate tracks, shuffle order and position by entry',
    () async {
      final original = [for (var i = 0; i < 8; i++) song(i)];
      final shuffled = original.reversed.toList();
      memory
        ..saveQueue(shuffled, original, 2)
        ..savePosition('entry5', const Duration(seconds: 37));
      await memory.flush();
      // Reopen the actual Hive file, as the next app launch does.
      await Hive.box('userNoBackup').close();
      await Hive.openBox('userNoBackup');
      final restored = QueuePersistenceService().read()!;
      expect(
        restored.songs.map((s) => s['queueEntryId']),
        shuffled.map((s) => s['queueEntryId']),
      );
      expect(
        restored.original.map((s) => s['queueEntryId']),
        original.map((s) => s['queueEntryId']),
      );
      expect(restored.index, 2);
      expect(restored.position, const Duration(seconds: 37));
      expect(restored.songs.first.containsKey('url'), isFalse);
      expect(restored.songs.first['audioPath'], '/music/7.wav');
    },
  );

  test(
    'the song last positioned is current; past its end starts at zero',
    () async {
      memory
        ..saveQueue([song(0), song(5)], [], 1)
        ..savePosition('entry0', const Duration(seconds: 30));
      await memory.flush();
      expect(memory.read()!.index, 0);
      expect(memory.read()!.position, const Duration(seconds: 30));
      memory.savePosition('entry5', const Duration(minutes: 5));
      await memory.flush();
      expect(memory.read()!.index, 1);
      expect(memory.read()!.position, Duration.zero);
    },
  );

  test(
    'large queues keep a bounded window containing the current entry',
    () async {
      final songs = [for (var i = 0; i < 2400; i++) song(i)];
      memory.saveQueue(songs, songs.reversed.toList(), 2250);
      await memory.flush();
      final saved = memory.read()!;
      expect(saved.songs, hasLength(QueuePersistenceService.limit));
      expect(saved.songs[saved.index]['queueEntryId'], 'entry2250');
      expect(saved.original, hasLength(QueuePersistenceService.limit));
      expect(saved.original.first['queueEntryId'], 'entry2399');
    },
  );

  test(
    'queue edits coalesce and clearing cannot resurrect old songs',
    () async {
      memory
        ..saveQueue([song(1)], [], 0)
        ..saveQueue([song(2)], [], 0);
      await memory.flush();
      expect(memory.read()!.songs.single['queueEntryId'], 'entry2');
      memory.saveQueue([], [], -1);
      await memory.flush();
      expect(memory.read(), isNull);
    },
  );

  test('malformed storage is ignored without losing the library', () async {
    final box = Hive.box('userNoBackup');
    for (final invalid in [
      'broken',
      {
        'version': 2,
        'songs': [song(1)],
      },
      {
        'version': 1,
        'songs': [song(1)],
        'index': 20,
      },
      {
        'version': 1,
        'songs': [song(1), song(1)],
        'index': 0,
      },
      {
        'version': 1,
        'songs': [song(1), null],
        'index': 0,
      },
    ]) {
      await box.put(QueuePersistenceService.queueKey, invalid);
      expect(memory.read(), isNull);
    }
  });

  test(
    'a track change in the same queue only moves the position record',
    () async {
      final songs = [for (var i = 0; i < 6; i++) song(i)];
      memory.saveQueue(songs, songs, 1);
      await memory.flush();
      final written = Hive.box('userNoBackup')
          .get(QueuePersistenceService.queueKey);

      memory.saveQueue(songs, songs, 4);
      await memory.flush();

      expect(
        Hive.box('userNoBackup').get(QueuePersistenceService.queueKey),
        same(written),
      );
      final restored = QueuePersistenceService().read()!;
      expect(restored.index, 4);
      expect(restored.position, Duration.zero);
      expect(
        restored.original.map((s) => s['queueEntryId']),
        songs.map((s) => s['queueEntryId']),
      );
    },
  );

  test(
    'restores radio continuation and resets it for an ordinary playlist',
    () async {
      final songs = [song(1), song(2)];
      memory.saveQueue(songs, songs, 0, keepGoing: true);
      await memory.flush();
      await Hive.box('userNoBackup').close();
      await Hive.openBox('userNoBackup');
      expect(QueuePersistenceService().read()!.keepGoing, isTrue);
      memory.saveQueue(songs, songs, 0);
      await memory.flush();
      expect(QueuePersistenceService().read()!.keepGoing, isFalse);
      final box = Hive.box('userNoBackup');
      await box.put(
        QueuePersistenceService.queueKey,
        Map.of(box.get(QueuePersistenceService.queueKey) as Map)
          ..remove('keepGoing'),
      );
      expect(QueuePersistenceService().read()!.keepGoing, isFalse);
    },
  );
}
