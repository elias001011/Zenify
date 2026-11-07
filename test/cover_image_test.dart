import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:musify/utilities/cover_image.dart';

void main() {
  // A noisy photo-sized picture: large as a file, as a camera's would be.
  Uint8List photo() {
    final random = Random(1);
    final image = img.Image(width: 3000, height: 2000);
    for (final pixel in image) {
      pixel
        ..r = random.nextInt(256)
        ..g = random.nextInt(256)
        ..b = random.nextInt(256);
    }
    return img.encodeJpg(image, quality: 95);
  }

  test('a large photo becomes a small cover', () {
    final bytes = photo();
    expect(bytes.length, greaterThan(1024 * 1024));
    final smaller = shrinkCover(bytes);
    expect(smaller.length, lessThan(bytes.length ~/ 4));
    final decoded = img.decodeImage(smaller)!;
    expect(decoded.width, coverSide);
    expect(decoded.height, 427);
  });

  test('a small cover and what is no image are left alone', () {
    final small = Uint8List.fromList(List.filled(1000, 1));
    expect(identical(shrinkCover(small), small), isTrue);
    final junk = Uint8List.fromList(List.filled(300 * 1024, 7));
    expect(identical(shrinkCover(junk), junk), isTrue);
  });

  test('a stored data URI is shrunk, or kept as it is', () async {
    final bytes = photo();
    final uri = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    final smaller = await shrinkCoverDataUri(uri);
    expect(smaller.length, lessThan(uri.length ~/ 4));
    expect(smaller, startsWith('data:image/jpeg;base64,'));
    expect(
      await shrinkCoverDataUri('https://example.com/a.jpg'),
      isNot(startsWith('data:')),
    );
    const tiny = 'data:image/png;base64,AAAA';
    expect(await shrinkCoverDataUri(tiny), tiny);
  });
}
