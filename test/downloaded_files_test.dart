import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/io_service.dart';

void main() {
  test('recognises only files Musify downloaded', () {
    expect(
      FilePaths.isDownloadedFile('/a/tracks/dQw4w9WgXcQ.m4a', artwork: false),
      isTrue,
    );
    expect(
      FilePaths.isDownloadedFile(
        r'C:\a\artworks\dQw4w9WgXcQ.jpg',
        artwork: true,
      ),
      isTrue,
    );
    expect(
      FilePaths.isDownloadedFile('/a/tracks/my song.m4a', artwork: false),
      isFalse,
    );
    expect(
      FilePaths.isDownloadedFile('/a/tracks/dQw4w9WgXcQ.jpg', artwork: false),
      isFalse,
    );
  });

  test('deleteDownloadedFiles removes ours and keeps the user files', () async {
    final root = await Directory.systemTemp.createTemp('musify_downloads');
    addTearDown(() => root.delete(recursive: true));
    applicationDirPath = root.path;
    final tracks = Directory('${root.path}/${FilePaths.tracksDir}')
      ..createSync();
    final legacy = Directory('${root.path}/legacy')..createSync();

    final ours = File('${tracks.path}/dQw4w9WgXcQ.m4a')..writeAsStringSync('');
    final mine = File('${tracks.path}/holiday.m4a')..writeAsStringSync('');
    final elsewhere = File('${legacy.path}/aaaaaaaaaaa.m4a')
      ..writeAsStringSync('');

    await FilePaths.deleteDownloadedFiles([
      {'ytid': 'aaaaaaaaaaa', 'audioPath': elsewhere.path},
    ]);

    expect(ours.existsSync(), isFalse);
    expect(elsewhere.existsSync(), isFalse);
    expect(mine.existsSync(), isTrue);
  });
}
