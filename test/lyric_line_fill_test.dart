import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/now_playing/lyric_line_fill.dart';

void main() {
  testWidgets('the highlight fades through intermediate brightness', (
    tester,
  ) async {
    final capture = GlobalKey();
    Widget verse(double emphasis) => MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: capture,
          child: ColoredBox(
            color: Colors.black,
            child: SizedBox(
              width: 180,
              child: LyricLineFill(
                text: 'AAAA AAAA',
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Ahem',
                  fontSize: 20,
                  decoration: TextDecoration.none,
                ),
                progress: 1,
                emphasis: emphasis,
                duration: const Duration(milliseconds: 300),
              ),
            ),
          ),
        ),
      ),
    );
    Future<double> brightness() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      final image = (await tester.runAsync(boundary.toImage))!;
      final data = (await tester.runAsync(image.toByteData))!;
      var total = 0;
      for (var i = 0; i < image.width * image.height * 4; i += 4) {
        total += data.getUint8(i);
      }
      final mean = total / (image.width * image.height);
      image.dispose();
      return mean;
    }

    await tester.pumpWidget(verse(1));
    await tester.pump();
    final bright = await brightness();
    await tester.pumpWidget(verse(0));
    await tester.pump(const Duration(milliseconds: 100));
    final middle = await brightness();
    await tester.pump(const Duration(milliseconds: 300));
    final dim = await brightness();
    expect(middle, greaterThan(dim + 5));
    expect(middle, lessThan(bright - 5));
    await tester.pumpWidget(const SizedBox());
  });

  for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
    testWidgets('wrapped verses fill one line before the next ($direction)', (
      tester,
    ) async {
      final capture = GlobalKey();
      Future<List<int>> paint(double progress) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: RepaintBoundary(
                key: capture,
                child: ColoredBox(
                  color: Colors.black,
                  child: SizedBox(
                    width: 180,
                    child: Directionality(
                      textDirection: direction,
                      child: LyricLineFill(
                        text: 'AAAA AAAA AAAA AAAA',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          height: 1.4,
                          fontFamily: 'Ahem',
                        ),
                        progress: progress,
                        duration: Duration.zero,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        final image = (await tester.runAsync(boundary.toImage))!;
        final data = (await tester.runAsync(image.toByteData))!;
        final bright = [0, 0];
        for (var y = 0; y < image.height; y++) {
          for (var x = 0; x < image.width; x++) {
            if (data.getUint8((y * image.width + x) * 4) > 220) {
              bright[y < image.height / 2 ? 0 : 1]++;
            }
          }
        }
        image.dispose();
        return bright;
      }

      final first = await paint(0.25);
      expect(first[0], greaterThan(0));
      expect(first[1], 0, reason: 'The next visual line must remain unfilled');
      final second = await paint(0.75);
      expect(second[0], greaterThan(first[0]));
      expect(second[1], greaterThan(0));
      final finished = await paint(1);
      expect(finished[0], second[0]);
      expect(finished[1], greaterThan(second[1]));
      await tester.pumpWidget(const SizedBox());
    });
  }
}
