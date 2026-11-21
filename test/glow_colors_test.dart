import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/artwork_colors.dart';
import 'package:musify/widgets/artwork_glow.dart';

void main() {
  const red = Color(0xFFFF0000);
  const blue = Color(0xFF0000FF);

  testWidgets('glows start clean and keep their state when reused', (
    tester,
  ) async {
    final colors = GlowColors(const TestVSync());
    addTearDown(colors.dispose);

    colors.update([null], red);
    expect(colors.colorAt(0)!.a, 0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));
    expect(colors.colorAt(0), red);
    colors.update([null], red);
    expect(colors.colorAt(0), red);

    colors.update([null], blue);
    expect(colors.colorAt(0), red);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final midway = colors.colorAt(0)!;
    expect(midway.r, greaterThan(0));
    expect(midway.b, greaterThan(0));

    await tester.pump(const Duration(milliseconds: 700));
    expect(colors.colorAt(0), blue);
  });

  testWidgets('a revisited cached page is immediately static', (tester) async {
    final first = GlowColors(const TestVSync(), cacheKey: 'cached-test-page')
      ..update([null], red);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(first.reveal, 1);
    first.dispose();
    final revisited = GlowColors(
      const TestVSync(),
      cacheKey: 'cached-test-page',
    )..update([null], red);
    expect(revisited.reveal, 1);
    expect(revisited.colorAt(0), red);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
    revisited.dispose();
  });

  testWidgets('a cached page keeps its glow while retrying artwork', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('zenify_glow_reopen');
    addTearDown(() => dir.deleteSync(recursive: true));
    final art = File('${dir.path}/cover.png');
    const cacheKey = 'cached-page-with-missing-artwork';

    final first = GlowColors(const TestVSync(), cacheKey: cacheKey);
    await tester.runAsync(() async {
      first.update([art.path], red);
      expect(await ArtworkColors.of(art.path), isNull);
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(first.colorAt(0), red);
    first.dispose();

    final revisited = GlowColors(const TestVSync(), cacheKey: cacheKey);
    addTearDown(revisited.dispose);
    final artworkColor = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(blue, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(24, 24);
      picture.dispose();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      await art.writeAsBytes(png!.buffer.asUint8List());

      revisited.update([art.path], red);
      expect(revisited.reveal, 1);
      expect(revisited.colorAt(0), red);
      final color = await ArtworkColors.of(art.path);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      return color;
    });
    expect(artworkColor, isNotNull);
    expect(revisited.colorAt(0), artworkColor);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('a glow that goes away fades out', (tester) async {
    final colors = GlowColors(const TestVSync());
    addTearDown(colors.dispose);

    colors.update([null, null], red);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));
    colors.update([null], red);
    expect(colors.colorAt(1)!.a, 1);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));
    expect(colors.colorAt(1), isNull);
    expect(colors.colorAt(0), red);
  });

  testWidgets('the glow expands once, not again for new colours', (
    tester,
  ) async {
    final colors = GlowColors(const TestVSync());
    addTearDown(colors.dispose);

    expect(colors.reveal, 0);
    colors.update([null], red);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(colors.reveal, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 800));
    expect(colors.reveal, 1);

    colors.update([null], blue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(colors.reveal, 1);
    await tester.pump(const Duration(milliseconds: 1300));
  });

  testWidgets('a glow keeps its colour while the next one is read', (
    tester,
  ) async {
    final colors = GlowColors(const TestVSync());
    addTearDown(colors.dispose);

    colors.update([null], red);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1500));
    // A file that doesn't exist: reading it takes a while and finds nothing.
    colors.update(['/nonexistent/artwork.png'], red);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(colors.colorAt(0), red);
    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets(
    'suspending stops active frames and can resume a partial reveal',
    (tester) async {
      final colors = GlowColors(const TestVSync())..update([null], red);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(colors.reveal, inExclusiveRange(0, 1));
      colors.suspend();
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
      final reveal = colors.reveal;
      await tester.pump(const Duration(seconds: 2));
      expect(colors.reveal, reveal);
      colors.update([null], red);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(colors.reveal, 1);
      expect(colors.colorAt(0), red);
      colors.dispose();
    },
  );

  testWidgets(
    'a failed artwork read retries when the same page updates again',
    (tester) async {
      late Directory dir;
      late File art;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('zenify_glow_retry');
        art = File('${dir.path}/cover.png');
      });
      addTearDown(() => dir.deleteSync(recursive: true));

      final colors = GlowColors(const TestVSync());
      addTearDown(colors.dispose);

      // First update while the file is still missing: falls back to red.
      await tester.runAsync(() async {
        colors.update([art.path], red);
        await Future<void>.delayed(const Duration(milliseconds: 220));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1500));
      expect(colors.colorAt(0), red);

      // The artwork arrives while the page is still open and updates again.
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 24, 24),
          Paint()..color = const Color(0xFF0055FF),
        );
        final img = await recorder.endRecording().toImage(24, 24);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        await art.writeAsBytes(png!.buffer.asUint8List());
        colors.update([art.path], red);
        for (var i = 0; i < 5; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));
        }
      });
      await tester.pump(const Duration(milliseconds: 1500));
      expect(colors.colorAt(0), isNot(red));
    },
  );
}
