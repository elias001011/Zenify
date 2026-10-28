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

import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart';

/// Sound waves in the app colour, shaped like the app icon, moving while
/// music plays. The player has no audio spectrum, so the motion is drawn.
class WaveVisualizer extends StatefulWidget {
  const WaveVisualizer({super.key, required this.size});

  final double size;

  @override
  State<WaveVisualizer> createState() => _WaveVisualizerState();
}

class _WaveVisualizerState extends State<WaveVisualizer>
    with SingleTickerProviderStateMixin {
  late final _time = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  );
  late final StreamSubscription<bool> _playing;

  @override
  void initState() {
    super.initState();
    _playing = audioHandler.playbackState
        .map((state) => state.playing)
        .distinct()
        .listen((playing) => playing ? _time.repeat() : _time.stop());
  }

  @override
  void dispose() {
    _playing.cancel();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _WavePainter(
          time: _time,
          colors: [colorScheme.primary, colorScheme.tertiary],
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.time, required this.colors})
    : super(repaint: time);

  final Animation<double> time;
  final List<Color> colors;

  static const _bars = 21;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / (_bars - 0.4);
    final barWidth = step * 0.6;
    final t = time.value * 2 * pi;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(Offset.zero & size);

    for (var i = 0; i < _bars; i++) {
      final x = (i - (_bars - 1) / 2) / ((_bars - 1) / 2);
      // Bell-shaped like the icon, each bar breathing at its own pace.
      final envelope = exp(-x * x * 2.2);
      final motion =
          0.55 +
          0.25 * sin(t * (2 + i % 3) + i * 1.7) +
          0.2 * sin(t * (5 + i % 4) + i * 0.6);
      final height = max(barWidth, size.height * 0.85 * envelope * motion);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(i * step + barWidth / 2, size.height / 2),
            width: barWidth,
            height: height,
          ),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) => oldDelegate.colors != colors;
}
