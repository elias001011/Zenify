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
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart';
import 'package:musify/services/audio_levels.dart';
import 'package:musify/services/settings_manager.dart';

/// Sound waves: they follow the music's frequencies with the precise
/// [waveReading] and keep a motion of their own otherwise. Pausing or
/// buffering freezes the bars in place.
class WaveVisualizer extends StatefulWidget {
  const WaveVisualizer({super.key, required this.size, this.compact = false});

  final double size;

  /// For the mini player's thumbnail, always on screen, which draws only as
  /// often as it needs: a step per audio reading (at most ~15 a second) with
  /// the precise reading, otherwise a slower motion of its own (8 a second),
  /// and no frames in between. The open player uses a ticker.
  final bool compact;

  @override
  State<WaveVisualizer> createState() => _WaveVisualizerState();
}

class _WaveVisualizerState extends State<WaveVisualizer>
    with SingleTickerProviderStateMixin {
  late final _bars = widget.compact ? 7 : 9;
  late final _heights = List<double>.generate(
    _bars,
    (i) => 0.18 + 0.28 * (1 - (i - (_bars - 1) / 2).abs() / (_bars / 2)),
  );
  final _repaint = ValueNotifier<int>(0);
  late final Ticker _ticker = createTicker(_tick);
  late final StreamSubscription<PlaybackState> _playingSubscription;
  late final StreamSubscription<String?> _trackSubscription;
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<AudioLevel>? _levels;
  Timer? _thumbnailTimer;
  Timer? _stale;
  AudioLevel? _level;
  bool _ready = false;
  bool _visible = true;
  bool _tickerEnabled = true;
  bool _connecting = false;
  Duration _last = Duration.zero;
  final _clock = Stopwatch()..start();
  Duration _lastStep = Duration.zero;
  double _time = 0;
  double _beat = 0;

  bool get _moving => _ready && _visible && _tickerEnabled;

  @override
  void initState() {
    super.initState();
    _setVisibility(WidgetsBinding.instance.lifecycleState);
    _lifecycle = AppLifecycleListener(onStateChange: _setVisibility);
    _playingSubscription = audioHandler.playbackState
        .distinct(
          (a, b) =>
              a.playing == b.playing && a.processingState == b.processingState,
        )
        .listen((state) {
          _ready =
              state.playing &&
              state.processingState == AudioProcessingState.ready;
          if (!_ready) _clearLevel();
          if (_ready) unawaited(_connect());
          _updateMotion();
        });
    _trackSubscription = audioHandler.mediaItem
        .map((item) => item?.id)
        .distinct()
        .listen((_) {
          _clearLevel();
          _updateMotion();
        });
    waveReading.addListener(_onReadingChanged);
  }

  void _onReadingChanged() {
    unawaited(_levels?.cancel());
    _levels = null;
    _clearLevel();
    if (_ready) unawaited(_connect());
    _updateMotion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _updateMotion();
  }

  void _setVisibility(AppLifecycleState? state) {
    _visible = state == null || state == AppLifecycleState.resumed;
    _updateMotion();
  }

  void _clearLevel() {
    _stale?.cancel();
    _level = null;
    _beat = 0;
  }

  Future<void> _connect() async {
    if (_levels != null || _connecting) return;
    _connecting = true;
    try {
      if (await AudioLevels.available && mounted) {
        _levels = AudioLevels.listen().listen((level) {
          if (!_ready) return;
          _level = level;
          _stale?.cancel();
          _stale = Timer(const Duration(milliseconds: 600), () {
            _level = null;
            _updateMotion();
          });
          if (widget.compact) _stepThumbnail();
          _updateMotion();
        });
      }
    } finally {
      _connecting = false;
    }
  }

  void _updateMotion() {
    if (!_moving) {
      _ticker.stop();
      _last = Duration.zero;
      _thumbnailTimer?.cancel();
      _thumbnailTimer = null;
    } else if (widget.compact) {
      if (_level == null) {
        _thumbnailTimer ??= Timer.periodic(
          const Duration(milliseconds: 125),
          (_) => _advance(0.125),
        );
      } else {
        _thumbnailTimer?.cancel();
        _thumbnailTimer = null;
      }
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _stepThumbnail() {
    if (!_moving) return;
    final now = _clock.elapsed;
    final since = now - _lastStep;
    if (since < const Duration(milliseconds: 66)) return;
    _lastStep = now;
    _advance(min(since.inMicroseconds / 1e6, 0.2));
  }

  void _tick(Duration elapsed) {
    final dt = min((elapsed - _last).inMicroseconds / 1e6, 0.1);
    _last = elapsed;
    _advance(dt);
  }

  void _advance(double dt) {
    _time += dt;
    final level = _level;
    _beat = max(level?.onset ?? 0, _beat * pow(0.02, dt).toDouble());
    for (var i = 0; i < _bars; i++) {
      final reach = (i - (_bars - 1) / 2).abs() / ((_bars - 1) / 2);
      final double target;
      if (level != null) {
        final index = (reach * (AudioLevels.bandCount - 1)).round();
        final band = index < level.bands.length
            ? level.bands[index]
            : level.loud;
        target =
            0.08 +
            band * 0.62 * (1 - 0.2 * reach) +
            _beat * 0.3 * pow(1 - reach, 2) +
            level.loud * 0.03 * sin(_time * 6 + i * 1.7);
      } else {
        target =
            (0.3 +
                0.14 * sin(_time * 2.1 + i * 0.8) +
                0.08 * sin(_time * 3.3 - i * 1.2)) *
            (1 - 0.3 * reach);
      }
      final rate = target > _heights[i] ? 30.0 : 7.0;
      _heights[i] += (target - _heights[i]) * (1 - exp(-rate * dt));
    }
    _repaint.value++;
  }

  @override
  void dispose() {
    waveReading.removeListener(_onReadingChanged);
    _lifecycle.dispose();
    _thumbnailTimer?.cancel();
    _stale?.cancel();
    unawaited(_playingSubscription.cancel());
    unawaited(_trackSubscription.cancel());
    unawaited(_levels?.cancel());
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: widget.size,
    child: RepaintBoundary(
      child: CustomPaint(
        size: Size.square(widget.size),
        painter: _WavePainter(
          heights: _heights,
          repaint: _repaint,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );
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
    final rect = (Offset.zero & size).deflate(size.width * 0.04);
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
