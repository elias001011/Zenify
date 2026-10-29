import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/queue_persistence_service.dart';

Map song(int index) => {
  'ytid': 'song${index % 5}',
  'queueEntryId': 'entry$index',
  'title': 'Track $index',
  'duration': 180,
  'url': 'expired',
  'audioPath': '/music/$index.wav',
};

void main() {
  late Directory directory;
  late QueuePersistenceService memory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('zenify_queue');
    Hive.init(directory.path);
    await Hive.openBox('userNoBackup');
  });
  setUp(() async {
    await Hive.box('userNoBackup').clear();
    memory = QueuePersistenceService();
  });
  tearDown(() => memory.flush());
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
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

  test('another entry and out-of-range positions start from zero', () async {
    memory
      ..saveQueue([song(0), song(5)], [], 1)
      ..savePosition('entry0', const Duration(seconds: 30));
    await memory.flush();
    expect(memory.read()!.position, Duration.zero);
    memory.savePosition('entry5', const Duration(minutes: 5));
    await memory.flush();
    expect(memory.read()!.position, Duration.zero);
  });

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
}
