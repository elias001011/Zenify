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

/// The player's sound waves. Each bar follows a band of the music, bass in
/// the middle and treble at the ends, and beats push the middle, when
/// [AudioLevels] can read it; otherwise, and on a phone until the user
/// allows it, they keep a calm motion of their own.
class WaveVisualizer extends StatefulWidget {
  const WaveVisualizer({
    super.key,
    required this.size,
    this.offerAccess = false,
    this.compact = false,
  });

  final double size;

  /// Offers to ask for the access the levels need (the player, not the
  /// mini player's thumbnail).
  final bool offerAccess;

  /// For the mini player's thumbnail: moves only when a reading arrives, with
  /// no animation of its own, so it costs no frames between readings, none
  /// while paused and none while the player covers it.
  final bool compact;

  @override
  State<WaveVisualizer> createState() => _WaveVisualizerState();
}

class _WaveVisualizerState extends State<WaveVisualizer>
    with SingleTickerProviderStateMixin {
  static const _bars = 9;
  static const _rest = 0.08;

  /// The logo's shape, where the bars rest with nothing to follow.
  static const _shape = [.3, .56, .4, .8, 1.0, .8, .4, .56, .3];

  late final Ticker _ticker = createTicker(_tick);

  /// Bumped every time the bars move, to repaint them.
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
    if (widget.compact) _restInShape();
    _playingSubscription = audioHandler.playbackState
        .map((state) => state.playing)
        .distinct()
        .listen(_onPlaying);
    unawaited(_connect());
  }

  void _restInShape() {
    for (var i = 0; i < _bars; i++) {
      _heights[i] = _shape[i] * 0.6;
    }
  }

  void _onPlaying(bool playing) {
    _playing = playing;
    if (widget.compact) {
      if (!playing) {
        _restInShape();
        _repaint.value++;
      }
    } else if (playing && !_ticker.isActive) {
      _ticker.start();
    }
  }

  Future<void> _connect() async {
    if (await AudioLevels.available) {
      if (!mounted) return;
      _levels = AudioLevels.listen().listen(_onLevel);
    } else if (widget.offerAccess && AudioLevels.canAsk && mounted) {
      setState(() => _canAsk = true);
    }
  }

  void _onLevel(AudioLevel level) {
    _level = level;
    // The thumbnail steps once per reading, and not while hidden.
    if (!widget.compact || !_playing || !TickerMode.valuesOf(context).enabled) {
      return;
    }
    _beat = max(level.onset, _beat * 0.6);
    for (var i = 0; i < _bars; i++) {
      final target = _target(i, level, 0);
      _heights[i] +=
          (target - _heights[i]) * (target > _heights[i] ? 0.7 : 0.3);
    }
    _repaint.value++;
  }

  Future<void> _ask() async {
    if (await AudioLevels.requestAccess() && mounted) {
      setState(() => _canAsk = false);
      await _connect();
    }
  }

  /// Where bar [i] heads for [level] at time [t] (seconds).
  double _target(int i, AudioLevel level, double t) {
    // 0 in the middle to 4 at the ends: the band the bar follows.
    final side = (i - (_bars - 1) ~/ 2).abs();
    final reach = side / ((_bars - 1) / 2);
    final band = side < level.bands.length ? level.bands[side] : level.loud;
    return _rest +
        band * 0.62 * (1 - 0.2 * reach) +
        _beat * 0.3 * (1 - reach) * (1 - reach) +
        level.loud * 0.03 * sin(t * 6 + i * 1.7);
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
      final double target;
      if (!_playing) {
        target = _rest;
      } else if (level != null) {
        target = _target(i, level, t);
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
