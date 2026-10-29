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

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/services/audio_levels.dart';
import 'package:musify/widgets/app_logo.dart';

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

  /// For the mini player's thumbnail, which is always on screen: it moves
  /// once per reading and has no animation of its own, so it asks for no
  /// frames between readings, while paused, without access to the audio or
  /// while the player covers it.
  final bool compact;

  @override
  State<WaveVisualizer> createState() => _WaveVisualizerState();
}

class _WaveVisualizerState extends State<WaveVisualizer>
    with SingleTickerProviderStateMixin {
  late final _bars = widget.compact ? 7 : 9;
  static const _rest = 0.08;

  late final Ticker _ticker = createTicker(_tick);

  /// Bumped every time the bars move, to repaint them.
  final _repaint = ValueNotifier<int>(0);
  late final _heights = List<double>.filled(_bars, _rest);
  late final StreamSubscription<PlaybackState> _playingSubscription;
  late final StreamSubscription<String?> _trackSubscription;
  StreamSubscription<AudioLevel>? _levels;
  AudioLevel? _level;
  final _clock = Stopwatch()..start();
  Duration? _lastReading;
  bool _connecting = false;
  bool _reconnect = false;
  bool _playing = false;
  bool _loading = false;
  bool _canAsk = false;
  double _beat = 0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _playingSubscription = audioHandler.playbackState
        .distinct(
          (a, b) =>
              a.playing == b.playing && a.processingState == b.processingState,
        )
        .listen(_onPlayback);
    _trackSubscription = audioHandler.mediaItem
        .map((item) => item?.id)
        .distinct()
        .listen((_) {
          _level = null;
          _lastReading = null;
          _beat = 0;
          _repaint.value++;
        });
    AudioLevels.accessChanged.addListener(_onAccessChanged);
    unawaited(_connect());
  }

  void _onPlayback(PlaybackState state) {
    _playing = state.playing;
    if (_playing && _levels == null) unawaited(_connect());
    _loading =
        state.processingState == AudioProcessingState.loading ||
        state.processingState == AudioProcessingState.buffering;
    if (_loading || !_playing) {
      _level = null;
      _lastReading = null;
      _beat = 0;
    }
    _repaint.value++;
    if (!widget.compact && _playing && !_ticker.isActive) _ticker.start();
  }

  bool get _freshReading =>
      !_loading &&
      _lastReading != null &&
      _clock.elapsed - _lastReading! < const Duration(milliseconds: 600);

  // Use the same painter as the app logo while loading, paused or waiting
  // for capture to recover. Synthetic motion is only for the player's waves
  // without access; the thumbnail shows the logo instead.
  bool get _showLogo =>
      !_playing ||
      _loading ||
      ((widget.compact || _levels != null) && !_freshReading);

  void _onAccessChanged() => unawaited(_connect());

  Future<void> _connect() async {
    if (_levels != null) return;
    if (_connecting) {
      _reconnect = true;
      return;
    }
    _connecting = true;
    try {
      final available = await AudioLevels.available;
      if (!mounted) return;
      if (available) {
        _levels = AudioLevels.listen().listen(_onLevel);
        if (_canAsk) setState(() => _canAsk = false);
      } else if (widget.offerAccess && AudioLevels.canAsk) {
        setState(() => _canAsk = true);
      }
    } finally {
      _connecting = false;
      if (_reconnect && mounted) {
        _reconnect = false;
        unawaited(_connect());
      }
    }
  }

  void _onLevel(AudioLevel level) {
    if (_loading || !_playing) return;
    _level = level;
    _lastReading = _clock.elapsed;
    if (widget.compact) _stepThumbnail(level);
  }

  Timer? _stale;
  Duration _lastStep = Duration.zero;

  void _stepThumbnail(AudioLevel level) {
    // Back to the logo if readings stop coming.
    _stale?.cancel();
    _stale = Timer(const Duration(milliseconds: 600), () {
      if (mounted) _repaint.value++;
    });
    if (!TickerMode.valuesOf(context).enabled) return;
    final now = _clock.elapsed;
    final dt = min((now - _lastStep).inMicroseconds / 1e6, 0.1);
    _lastStep = now;
    final t = now.inMicroseconds / 1e6;
    _beat = max(level.onset, _beat * pow(0.02, dt).toDouble());
    for (var i = 0; i < _bars; i++) {
      final target = _target(i, level, t);
      final rate = target > _heights[i] ? 30.0 : 7.0;
      _heights[i] += (target - _heights[i]) * (1 - exp(-rate * dt));
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
    final index = (reach * (AudioLevels.bandCount - 1)).round();
    final band = index < level.bands.length ? level.bands[index] : level.loud;
    return _rest +
        band * 0.62 * (1 - 0.2 * reach) +
        _beat * 0.3 * (1 - reach) * (1 - reach) +
        level.loud * 0.03 * sin(t * 6 + i * 1.7);
  }

  void _tick(Duration elapsed) {
    final dt = min((elapsed - _last).inMicroseconds / 1e6, 0.1);
    _last = elapsed;
    final t = elapsed.inMicroseconds / 1e6;
    final level = _freshReading ? _level : null;
    // A beat jumps up at once and fades over a fraction of a second.
    _beat = max(level?.onset ?? 0, _beat * pow(0.02, dt).toDouble());

    var settled = true;
    for (var i = 0; i < _bars; i++) {
      final double target;
      if (_showLogo) {
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
    AudioLevels.accessChanged.removeListener(_onAccessChanged);
    _stale?.cancel();
    _clock.stop();
    _playingSubscription.cancel();
    _trackSubscription.cancel();
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
                showLogo: () => _showLogo,
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
    required this.showLogo,
    required Listenable repaint,
    required this.color,
  }) : super(repaint: repaint);

  final List<double> heights;
  final bool Function() showLogo;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(size.width * 0.04);
    if (showLogo()) {
      paintZenifyWaves(canvas, rect, size.width, Paint()..color = color);
      return;
    }
    final step = rect.width / (heights.length - 0.4);
    final barWidth = step * 0.6;
    final paint = Paint()..color = color;
    for (var i = 0; i < heights.length; i++) {
      final height = max(barWidth, rect.height * heights[i].clamp(0, 1));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(
              rect.left + i * step + barWidth / 2,
              size.height / 2,
            ),
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
