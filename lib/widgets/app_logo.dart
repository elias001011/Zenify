/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     Musify is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Musify is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Musify, including how to contribute,
 *     please visit: https://github.com/gokadzev/Musify
 */

import 'dart:math';

import 'package:material_ui/material_ui.dart';

/// Bar heights of Zenify's waveform, by how many bars fit the size.
const _waveforms = {
  9: [.3, .56, .4, .8, 1.0, .8, .4, .56, .3],
  7: [.32, .6, .84, 1.0, .84, .6, .32],
  5: [.42, .76, 1.0, .76, .42],
};

/// Paints Zenify's waveform centred in [rect], filled with [paint]: [bars]
/// of them, or, without it, fewer and wider the smaller [pixels] (the size
/// it is drawn at), so they stay legible.
void paintZenifyWaves(
  Canvas canvas,
  Rect rect,
  double pixels,
  Paint paint, {
  int? bars,
}) {
  final heights =
      _waveforms[bars ?? (pixels >= 96 ? 9 : (pixels >= 40 ? 7 : 5))]!;
  // Bar, gap, bar...: bars take 60% of each step.
  final step = rect.width / (heights.length - 0.4);
  final barWidth = step * 0.6;
  for (var i = 0; i < heights.length; i++) {
    final height = max(barWidth, rect.height * heights[i]);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(rect.left + i * step + barWidth / 2, rect.center.dy),
          width: barWidth,
          height: height,
        ),
        Radius.circular(barWidth / 2),
      ),
      paint,
    );
  }
}

/// The app's logo in one colour, drawn at its size so it stays sharp.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _AppLogoPainter(color),
    );
  }
}

class _AppLogoPainter extends CustomPainter {
  const _AppLogoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Bars are counted by the logical size: what reads at a glance.
    final rect = (Offset.zero & size).deflate(size.width * 0.04);
    paintZenifyWaves(canvas, rect, size.width, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_AppLogoPainter oldDelegate) => oldDelegate.color != color;
}
