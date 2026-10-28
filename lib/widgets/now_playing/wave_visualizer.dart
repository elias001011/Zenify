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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/services/audio_levels.dart';

/// The player's sound waves. They follow the music, its loudness, beats and
/// treble, when [AudioLevels] can read it; otherwise, and on a phone until
/// the user allows it, they keep a calm motion of their own.
class WaveVisualizer extends StatefulWidget {
  const WaveVisualizer({
    super.key,
    required this.size,
    this.offerAccess = false,
  });

  final double size;

  /// Offers to ask for the access the levels need (the player, not the
  /// mini player's thumbnail).
  final bool offerAccess;

  @override
  State<WaveVisualizer> createState() => _WaveVisualizerState();
}

class _WaveVisualizerState extends State<WaveVisualizer>
    with SingleTickerProviderStateMixin {
  static const _bars = 9;
  static const _rest = 0.08;

  late final Ticker _ticker = createTicker(_tick);

  /// Bumped every frame the bars move, to repaint them.
  final _repaint = ValueNotifier<int>(0);
  final _heights = List<double>.filled(_bars, _rest);
  late final StreamSubscription<bool> _playingSubscription;
  StreamSubscription<AudioLevel>? _levels;
  AudioLevel? _level;
  bool _playing = false;
  bool _canAsk = false;
  double _beat = 0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _playingSubscription = audioHandler.playbackState
        .map((state) => state.playing)
        .distinct()
        .listen((playing) {
          _playing = playing;
          if (playing && !_ticker.isActive) _ticker.start();
        });
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (await AudioLevels.available) {
      if (!mounted) return;
      _levels = AudioLevels.listen().listen((level) => _level = level);
    } else if (widget.offerAccess && AudioLevels.canAsk && mounted) {
      setState(() => _canAsk = true);
    }
  }

  Future<void> _ask() async {
    if (await AudioLevels.requestAccess() && mounted) {
      setState(() => _canAsk = false);
      await _connect();
    }
  }

  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final t = elapsed.inMicroseconds / 1e6;
    final level = _level;
    // A beat jumps up at once and fades over a fraction of a second.
    _beat = max(level?.onset ?? 0, _beat * pow(0.02, dt).toDouble());

    var settled = true;
    for (var i = 0; i < _bars; i++) {
      // 0 in the middle, 1 at the ends: beats and bass push the middle, treble
      // lifts the sides.
      final side = (i - (_bars - 1) / 2).abs() / ((_bars - 1) / 2);
      final double target;
      if (!_playing) {
        target = _rest;
      } else if (level != null) {
        target =
            _rest +
            level.loud * 0.5 * (1 - 0.45 * side) +
            _beat * 0.38 * (1 - side * side) +
            level.loud * level.bright * 0.28 * side +
            level.loud * 0.05 * sin(t * 6 + i * 1.7);
      } else {
        target =
            0.25 +
            0.14 * sin(t * 2.1 + i * 0.8) +
            0.08 * sin(t * 3.3 - i * 1.2);
      }
      // Up quickly, down slowly, at the same speed whatever the frame rate.
      final rate = target > _heights[i] ? 30.0 : 7.0;
      _heights[i] += (target - _heights[i]) * (1 - exp(-rate * dt));
      if ((_heights[i] - target).abs() > 0.002) settled = false;
    }
    _repaint.value++;
    if (!_playing && settled) {
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  @override
  void dispose() {
    _playingSubscription.cancel();
    _levels?.cancel();
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _WavePainter(
                heights: _heights,
                repaint: _repaint,
                color: colorScheme.primary,
              ),
            ),
          ),
          if (_canAsk)
            TextButton.icon(
              onPressed: _ask,
              icon: const Icon(FluentIcons.data_bar_vertical_24_regular),
              label: Text(context.l10n!.wavesFollowMusic),
            ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.heights,
    required Listenable repaint,
    required this.color,
  }) : super(repaint: repaint);

  final List<double> heights;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / (heights.length + 2);
    final barWidth = step * 0.35;
    final paint = Paint()..color = color;
    for (var i = 0; i < heights.length; i++) {
      final height = max(barWidth, size.height * 0.8 * heights[i].clamp(0, 1));
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
