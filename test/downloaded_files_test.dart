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

  test('only paths inside our folders count as ours', () {
    downloadsDirPath = '/data/custom';
    applicationDirPath = '/home/u/.local/share/app';
    expect(FilePaths.isOwnDownload('/data/custom/tracks/x.m4a'), isTrue);
    expect(
      FilePaths.isOwnDownload('/home/u/.local/share/app/tracks/x.m4a'),
      isTrue,
    );
    expect(FilePaths.isOwnDownload('/home/u/Documents/tracks/x.m4a'), isFalse);
    expect(FilePaths.isOwnDownload('/data/custom-other/x.m4a'), isFalse);
  });

  test('deleteDownloadedFiles removes ours and keeps the user files', () async {
    final root = await Directory.systemTemp.createTemp('musify_downloads');
    addTearDown(() => root.delete(recursive: true));
    final other = await Directory.systemTemp.createTemp('musify_other');
    addTearDown(() => other.delete(recursive: true));
    downloadsDirPath = root.path;
    applicationDirPath = root.path;
    final tracks = Directory('${root.path}/${FilePaths.tracksDir}')
      ..createSync();
    final legacy = Directory('${root.path}/legacy')..createSync();

    final ours = File('${tracks.path}/dQw4w9WgXcQ.m4a')..writeAsStringSync('');
    final mine = File('${tracks.path}/holiday.m4a')..writeAsStringSync('');
    final elsewhere = File('${legacy.path}/aaaaaaaaaaa.m4a')
      ..writeAsStringSync('');

    // Another app's library, e.g. copied over from Musify's documents folder.
    final foreign = File('${other.path}/bbbbbbbbbbb.m4a')
      ..writeAsStringSync('');

    await FilePaths.deleteDownloadedFiles([
      {'ytid': 'aaaaaaaaaaa', 'audioPath': elsewhere.path},
      {'ytid': 'bbbbbbbbbbb', 'audioPath': foreign.path},
    ]);

    expect(ours.existsSync(), isFalse);
    expect(elsewhere.existsSync(), isFalse);
    expect(mine.existsSync(), isTrue);
    expect(foreign.existsSync(), isTrue);
  });
}
