import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:musify/utilities/cover_image.dart';
import 'package:musify/widgets/cover_image.dart';

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

  group('the CoverImage widget', () {
    late Directory dir;
    late String file;
    setUpAll(() {
      dir = Directory.systemTemp.createTempSync('cover_image_widget');
      file = '${dir.path}/cover.png';
      File(file)
          .writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
    });
    tearDownAll(() => dir.deleteSync(recursive: true));

    const url = 'https://i.ytimg.com/vi/abc/hqdefault.jpg';
    const error = Text('error');
    const placeholder = Text('loading');

    Widget host(Widget child, {double pixelRatio = 3}) => Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(devicePixelRatio: pixelRatio),
        child: Center(child: child),
      ),
    );

    // What the network branch draws once a picture arrived, built from the
    // builder CachedNetworkImage was given and a stand-in provider.
    Widget drawn(WidgetTester tester) {
      final network = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      return network.imageBuilder!(
        tester.element(find.byType(CoverImage)),
        FileImage(File(file)),
      );
    }

    testWidgets('draws a local file at the size and decodes it at that size', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const CoverImage(source: '', size: 52, error: error)),
      );
      expect(find.text('error'), findsOneWidget);

      await tester.pumpWidget(
        host(CoverImage(source: file, size: 52, error: error)),
      );
      expect(tester.getSize(find.byType(CoverImage)), const Size(52, 52));
      expect(find.byType(CachedNetworkImage), findsNothing);
      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image as ResizeImage;
      // 52 logical pixels on a screen of 3 pixels per logical pixel.
      expect(provider.width, 156);
      expect(provider.height, isNull);
      expect((provider.imageProvider as FileImage).file.path, file);
      expect(image.fit, BoxFit.cover);
      expect(
        tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
        BorderRadius.circular(10),
      );

      // The decode size follows the screen.
      await tester.pumpWidget(
        host(CoverImage(source: file, size: 52, error: error), pixelRatio: 2),
      );
      expect(
        (tester.widget<Image>(find.byType(Image)).image as ResizeImage).width,
        104,
      );

      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(find.text('error'), findsNothing);
    });

    testWidgets('shows the error widget for a file that is not there', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          CoverImage(source: '${dir.path}/none.png', size: 52, error: error),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      expect(find.text('error'), findsOneWidget);
    });

    testWidgets('puts the overlay over a local picture, inside its corners', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          CoverImage(
            source: file,
            size: 52,
            borderRadius: 26,
            error: error,
            overlay: const Positioned(top: 0, right: 0, child: Text('badge')),
          ),
        ),
      );
      final clip = find.byType(ClipRRect);
      expect(
        tester.widget<ClipRRect>(clip).borderRadius,
        BorderRadius.circular(26),
      );
      expect(
        find.descendant(of: clip, matching: find.text('badge')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: clip, matching: find.byType(Image)),
        findsOneWidget,
      );
    });

    testWidgets('fetches a URL as a cached network image, decoded at size', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const CoverImage(
            source: url,
            size: 52,
            placeholder: placeholder,
            error: error,
          ),
        ),
      );
      expect(tester.getSize(find.byType(CoverImage)), const Size(52, 52));
      final network = tester.widget<CachedNetworkImage>(
        find.byType(CachedNetworkImage),
      );
      expect(network.imageUrl, url);
      expect(network.memCacheWidth, 156);
      expect(network.memCacheHeight, isNull);
      expect(network.width, 52);
      expect(network.height, 52);
      // The same on-disk cache entry as any other use of the URL.
      expect(network.cacheKey, isNull);
      expect(network.cacheManager, isNull);
      // Until the picture arrives, the placeholder.
      expect(find.text('loading'), findsOneWidget);

      final context = tester.element(find.byType(CoverImage));
      expect(network.placeholder!(context, url), same(placeholder));
      expect(network.errorWidget!(context, url, 'failed'), same(error));
    });

    testWidgets('draws a downloaded picture at the same size as a file', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const CoverImage(source: url, size: 52, error: error)),
      );
      final clip = drawn(tester) as ClipRRect;
      expect(clip.borderRadius, BorderRadius.circular(10));
      final image = clip.child! as Image;
      expect((image.image as ResizeImage).width, 156);
      expect(image.width, 52);
      expect(image.height, 52);
      expect(image.fit, BoxFit.cover);
      expect(image.centerSlice, isNull);
    });

    testWidgets('stretches low-res thumbnails over their bars, if asked', (
      tester,
    ) async {
      const thumbnail = 'https://i.ytimg.com/vi/abc/default.jpg';
      Future<Image> picture(String source, {bool fill = true}) async {
        await tester.pumpWidget(
          host(
            CoverImage(
              source: source,
              size: 52,
              fillLetterbox: fill,
              error: error,
            ),
          ),
        );
        return (drawn(tester) as ClipRRect).child! as Image;
      }

      final stretched = await picture(thumbnail);
      expect(stretched.fit, BoxFit.fill);
      expect(stretched.centerSlice, const Rect.fromLTRB(1, 1, 1, 1));
      expect((await picture(thumbnail, fill: false)).fit, BoxFit.cover);
      // Only the thumbnails with bars, not any other picture.
      expect(
        (await picture('https://lh3.googleusercontent.com/x=w226')).fit,
        BoxFit.cover,
      );
    });

    testWidgets('puts the overlay over a downloaded picture only', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const CoverImage(
            source: url,
            size: 52,
            error: error,
            overlay: Positioned(top: 0, right: 0, child: Text('badge')),
          ),
        ),
      );
      // Not over the placeholder or the error, only over the picture.
      expect(find.text('badge'), findsNothing);
      final clip = drawn(tester) as ClipRRect;
      expect(clip.child, isA<Stack>());
      expect((clip.child! as Stack).children, hasLength(2));
    });
  });
}
