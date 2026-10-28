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

/// A restrained, single-colour playback animation. This is decorative,
/// not an audio spectrum; no audio samples are analysed.
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
        painter: _WavePainter(time: _time, color: colorScheme.primary),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.time, required this.color})
    : super(repaint: time);

  final Animation<double> time;
  final Color color;

  static const _bars = 9;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / (_bars + 2);
    final barWidth = step * 0.35;
    final t = time.value * 2 * pi;
    final paint = Paint()..color = color;
    for (var i = 0; i < _bars; i++) {
      final motion =
          0.5 + 0.25 * sin(t * 2 + i * 0.8) + 0.15 * sin(t * 3 - i * 1.2);
      final height = max(barWidth, size.height * 0.55 * motion);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset((i + 1.5) * step, size.height / 2),
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
  bool shouldRepaint(_WavePainter oldDelegate) => oldDelegate.color != color;
}
