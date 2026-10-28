import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/artwork_colors.dart';

List<int> _pixels(List<Color> colors) => [
  for (final c in colors) ...[
    (c.r * 255).round(),
    (c.g * 255).round(),
    (c.b * 255).round(),
    255,
  ],
];

void main() {
  test('prefers the vivid part of an artwork over its dull background', () {
    final pixels = _pixels([
      for (var i = 0; i < 80; i++) const Color(0xFF202020),
      for (var i = 0; i < 20; i++) const Color(0xFFE53935),
    ]);

    final color = ArtworkColors.vividColor(pixels)!;
    final hsv = HSVColor.fromColor(color);

    expect(
      hsv.hue,
      closeTo(HSVColor.fromColor(const Color(0xFFE53935)).hue, 4),
    );
    expect(hsv.saturation, greaterThanOrEqualTo(0.45));
    expect(hsv.value, greaterThanOrEqualTo(0.6));
  });

  test('grey artwork has no glow colour', () {
    final pixels = _pixels([
      for (var i = 0; i < 50; i++) const Color(0xFF808080),
      for (var i = 0; i < 50; i++) const Color(0xFF101010),
    ]);

    expect(ArtworkColors.vividColor(pixels), isNull);
  });

  test('transparent pixels are ignored', () {
    expect(ArtworkColors.vividColor([255, 0, 0, 0]), isNull);
  });
}
