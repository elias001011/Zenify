import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/artwork_glow.dart';

void main() {
  const red = Color(0xFFFF0000);
  const blue = Color(0xFF0000FF);

  testWidgets('glows show at once, then ease into new colours', (tester) async {
    final colors = GlowColors(const TestVSync());
    addTearDown(colors.dispose);

    // No artwork: the app colour, without a fade the first time.
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

  testWidgets('a glow that goes away fades out', (tester) async {
    final colors = GlowColors(const TestVSync());
    addTearDown(colors.dispose);

    colors
      ..update([null, null], red)
      ..update([null], red);
    expect(colors.colorAt(1)!.a, 1);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1300));
    expect(colors.colorAt(1)!.a, 0);
    expect(colors.colorAt(0), red);
  });
}
