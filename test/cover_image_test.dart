import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
      // The image cache of a network cover looks for its folders.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => dir.path,
          );
      file = '${dir.path}/cover.png';
      File(file)
          .writeAsBytesSync(img.encodePng(img.Image(width: 8, height: 8)));
    });
    tearDownAll(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      dir.deleteSync(recursive: true);
    });

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

    // A 'default.jpg': 4:3, black bars of 11 rows above and below the 16:9
    // picture, which is red with a white square in the middle.
    Uint8List thumbnailWithBars() {
      final image = img.Image(width: 120, height: 90);
      img.fill(image, color: img.ColorRgb8(0, 0, 0));
      img.fillRect(
        image,
        x1: 0,
        y1: 11,
        x2: 120,
        y2: 79,
        color: img.ColorRgb8(170, 34, 34),
      );
      img.fillRect(
        image,
        x1: 26,
        y1: 11,
        x2: 94,
        y2: 79,
        color: img.ColorRgb8(255, 255, 255),
      );
      return img.encodePng(image);
    }

    // The picture as it is shown on a [ratio] screen, over a blue background:
    // [check] gets the colours at the points [at] of the 52 px square.
    Future<void> shown(
      WidgetTester tester,
      String source, {
      required bool fill,
      required double ratio,
      required List<(int, int)> at,
      required void Function(List<Color>) check,
    }) async {
      await tester.pumpWidget(
        host(
          CoverImage(
            source: source,
            size: 52,
            fillLetterbox: fill,
            error: error,
          ),
          pixelRatio: ratio,
        ),
      );
      final key = GlobalKey();
      final picture =
          tester
              .widget<CachedNetworkImage>(find.byType(CachedNetworkImage))
              .imageBuilder!(
            tester.element(find.byType(CoverImage)),
            MemoryImage(thumbnailWithBars()),
          );
      await tester.pumpWidget(
        host(
          RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: const Color(0xFF2266AA),
              child: SizedBox.square(dimension: 52, child: picture),
            ),
          ),
          pixelRatio: ratio,
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      final image = (await tester.runAsync(boundary.toImage))!;
      final bytes = (await tester.runAsync(image.toByteData))!;
      Color pixel(int x, int y) {
        final i = (y * image.width + x) * 4;
        return Color.fromARGB(
          bytes.getUint8(i + 3),
          bytes.getUint8(i),
          bytes.getUint8(i + 1),
          bytes.getUint8(i + 2),
        );
      }

      check([for (final (x, y) in at) pixel(x, y)]);
    }

    testWidgets('crops the bars off low-res thumbnails, if asked', (
      tester,
    ) async {
      const thumbnail = 'https://i.ytimg.com/vi/abc/default.jpg';
      // Just inside each edge: all of it is the white square, with no black
      // bar and no gap showing the background.
      const edges = [(26, 2), (26, 49), (2, 26), (49, 26)];
      for (final ratio in [1.0, 2.0, 3.0]) {
        await shown(
          tester,
          thumbnail,
          fill: true,
          ratio: ratio,
          at: edges,
          check: (colors) {
            for (final color in colors) {
              expect(
                [color.r, color.g, color.b].every((c) => c > 0.85),
                isTrue,
                reason: 'ratio $ratio: $color should be the white square',
              );
            }
          },
        );
      }
      // Not asked for, or not a thumbnail with bars: the bars stay, as in any
      // other cropped picture.
      await shown(
        tester,
        thumbnail,
        fill: false,
        ratio: 1,
        at: const [(26, 2)],
        check: (colors) => expect(colors.single.r, lessThan(0.2)),
      );
      // The download that cannot happen here retries later.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 60));
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
