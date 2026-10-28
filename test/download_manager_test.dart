import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:musify/services/download_manager.dart';

void main() {
  late Directory dir;
  final manager = DownloadManager.instance;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('musify_downloads');
    Hive.init(dir.path);
    await Hive.openBox('userNoBackup');
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  setUp(manager.clearHistory);

  Map<String, dynamic> song(String id) => {
    'ytid': id,
    'title': 'Song $id',
    'artist': 'Artist',
  };

  test('tracks a download from start to finish and keeps it', () {
    final entry = manager.started(song('a'));
    expect(manager.active.single.ytid, 'a');

    manager
      ..finished(entry)
      ..flush();

    expect(manager.active, isEmpty);
    expect(entry.status, DownloadStatus.done);
    final stored = Hive.box('userNoBackup').get('downloadHistory') as List;
    expect((stored.single as Map)['status'], 'done');
  });

  test('a retry replaces the earlier entry for the same song', () {
    manager.failed(manager.started(song('b')), const SocketException('x'));
    manager.started(song('b'));

    expect(manager.entries.value.where((e) => e.ytid == 'b'), hasLength(1));
    expect(manager.entries.value.first.status, DownloadStatus.downloading);
  });

  test('failures are told apart', () {
    expect(DownloadManager.failureFor(null), DownloadFailure.unavailable);
    expect(
      DownloadManager.failureFor(const SocketException('offline')),
      DownloadFailure.network,
    );
    expect(
      DownloadManager.failureFor(http.ClientException('reset')),
      DownloadFailure.network,
    );
    expect(
      DownloadManager.failureFor(StateError('bad')),
      DownloadFailure.other,
    );
  });

  test('history round-trips through storage', () {
    final entry = manager.started(song('c'));
    manager
      ..failed(entry, null)
      ..flush();

    final restored = DownloadEntry.fromMap(
      (Hive.box('userNoBackup').get('downloadHistory') as List).first as Map,
    );
    expect(restored.ytid, 'c');
    expect(restored.status, DownloadStatus.failed);
    expect(restored.failure, DownloadFailure.unavailable);
  });

  test('history keeps only the latest finished downloads', () {
    for (var i = 0; i < 250; i++) {
      manager.finished(manager.started(song('h$i')));
    }
    manager.flush();

    final history = manager.entries.value.where(
      (e) => e.status != DownloadStatus.downloading,
    );
    expect(history, hasLength(200));
    expect(history.first.ytid, 'h249');
    expect(
      Hive.box('userNoBackup').get('downloadHistory') as List,
      hasLength(200),
    );
  });

  test('clearing history keeps downloads in progress', () {
    manager
      ..finished(manager.started(song('d')))
      ..started(song('e'))
      ..clearHistory();

    final entries = manager.entries.value;
    expect(entries.map((e) => e.ytid), contains('e'));
    expect(entries.map((e) => e.ytid), isNot(contains('d')));
    expect(
      entries.every((e) => e.status == DownloadStatus.downloading),
      isTrue,
    );
  });
}
