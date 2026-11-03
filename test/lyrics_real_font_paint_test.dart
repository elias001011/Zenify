import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/now_playing/lyric_line_fill.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('LyricTestFont')
      ..addFont(rootBundle.load('assets/fonts/paytone/PaytoneOne-Regular.ttf'));
    await loader.load();
  });
  for (final width in [160.0, 240.0, 350.0]) {
    for (final scale in [1.0, 1.5]) {
      for (final accessibleSpacing in [false, true]) {
        testWidgets(
          'centered real-font fill matches its paragraph ($width, $scale, accessible: $accessibleSpacing)',
          (tester) async {
            final capture = GlobalKey();
            const text =
                'A música atravessa a noite\nE encontra palavras pequenas e longas';
            const style = TextStyle(
              fontFamily: 'LyricTestFont',
              fontSize: 20,
              height: 1.4,
              color: Colors.white,
              fontWeight: FontWeight.w400,
              decoration: TextDecoration.none,
            );
            Future<(Size, Uint8List)> paint(bool filled) async {
              await tester.pumpWidget(
                MaterialApp(
                  home: MediaQuery(
                    data: MediaQueryData(
                      textScaler: TextScaler.linear(scale),
                      boldText: accessibleSpacing,
                      lineHeightScaleFactorOverride: accessibleSpacing
                          ? 1.65
                          : null,
                      letterSpacingOverride: accessibleSpacing ? 1.5 : null,
                      wordSpacingOverride: accessibleSpacing ? 3 : null,
                    ),
                    child: Center(
                      child: RepaintBoundary(
                        key: capture,
                        child: ColoredBox(
                          color: Colors.black,
                          child: SizedBox(
                            width: width,
                            child: filled
                                ? const LyricLineFill(
                                    text: text,
                                    style: style,
                                    progress: 1,
                                    textAlign: TextAlign.center,
                                    duration: Duration.zero,
                                  )
                                : const Text(
                                    text,
                                    style: style,
                                    textAlign: TextAlign.center,
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
              final bytes = (await tester.runAsync(image.toByteData))!;
              final result = (
                Size(image.width.toDouble(), image.height.toDouble()),
                Uint8List.fromList(bytes.buffer.asUint8List()),
              );
              image.dispose();
              return result;
            }

            final reference = await paint(false);
            final filled = await paint(true);
            expect(filled.$1, reference.$1);
            var difference = 0;
            for (var i = 0; i < reference.$2.length; i += 4) {
              difference += (filled.$2[i] - reference.$2[i]).abs();
            }
            expect(
              difference / (reference.$2.length / 4),
              lessThan(2),
              reason: 'The painted highlight must stay on the same glyphs and visual lines',
            );
            await tester.pumpWidget(const SizedBox());
          },
        );
      }
    }
  }
}
