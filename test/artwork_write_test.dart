import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/common_services.dart';

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('zenify_art'));
  tearDown(() => directory.deleteSync(recursive: true));

  test('a late attempt leaves the newer cover alone', () async {
    final path = '${directory.path}/artworks/song.jpg';

    final newer = await writeArtworkFile(path, [1, 2, 3]);
    final late = await writeArtworkFile(path, [9, 9], abandoned: () => true);

    expect(newer?.path, path);
    expect(late, isNull);
    expect(File(path).readAsBytesSync(), [1, 2, 3]);
    expect(Directory('${directory.path}/artworks').listSync().length, 1);
  });

  test('an empty body keeps nothing', () async {
    final path = '${directory.path}/song.jpg';

    expect(await writeArtworkFile(path, []), isNull);
    expect(directory.listSync(), isEmpty);
  });
}
