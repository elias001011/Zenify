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
import 'package:musify/widgets/playback_icon_button.dart';

/// Sound waves: they follow the music's frequencies with the precise
/// [waveReading] and keep a motion of their own otherwise. While nothing plays
/// (paused, buffering, loading) they go down to a row of dots and rest there
/// without drawing a frame. With the app out of view Flutter draws no frames,
/// so they stop by themselves; [AudioLevels] lets its reader go.
class WaveVisualizer extends StatefulWidget {
  const WaveVisualizer({super.key, required this.size});

  final double size;

  @override
  State<WaveVisualizer> createState() => _WaveVisualizerState();
}

class _WaveVisualizerState extends State<WaveVisualizer>
    with SingleTickerProviderStateMixin {
  /// The bars are drawn 48 times a second. The music is read less often, and
  /// the bars ease towards each reading, so the extra frames smooth the motion.
  static const _frameMicroseconds = 1000000 ~/ 48;

  /// A frame may come this early and still count as due, so a frame a hair
  /// ahead of the schedule is not skipped and the rate does not fall short.
  static const _earlyMicroseconds = 2000;

  /// After a pause the reader stays on this long, so a short one does not set
  /// it up again, and start it cold, at the resume.
  static const _readerGrace = Duration(seconds: 15);

  /// With the precise reading, how long after play the bars wait at rest for
  /// the first reading, rather than rise on their own motion and then jump to
  /// the music, which is louder.
  static const _musicWait = Duration(milliseconds: 600);

  /// A reading that is all zeros this soon after play is the reader warming up,
  /// not silence: the bars keep their own motion instead of falling to dots.
  static const _warmUp = Duration(milliseconds: 400);

  /// A reading older than this is no longer the music.
  static const _staleAfter = Duration(milliseconds: 600);

  final _motion = _WaveMotion();
  final _repaint = ValueNotifier<int>(0);
  late final Ticker _ticker = createTicker(_tick);
  late final StreamSubscription<PlaybackState> _playingSubscription;
  late final StreamSubscription<String?> _trackSubscription;
  StreamSubscription<AudioLevel>? _levels;
  Timer? _releaseReader;
  AudioLevel? _level;
  final _sinceLevel = Stopwatch();
  final _sincePlay = Stopwatch();
  bool _ready = false;
  bool _animating = true;

  /// The precise reading can be read: readings are on their way.
  bool _expectLevels = false;
  Duration _last = Duration.zero;

  /// When the next frame is due, in microseconds of the ticker's clock: kept as
  /// a schedule, so a screen that is not a multiple of 48 Hz still averages 48.
  int _due = 0;

  bool get _moving => _ready && _animating;
  bool get _precise => waveReading.value == WaveReading.precise;

  @override
  void initState() {
    super.initState();
    // The same state as the play button shows: a skip's moment of loading
    // does not send the bars down and up again.
    _playingSubscription = settledPlaybackState().listen((state) {
      final wasReady = _ready;
      _ready =
          state.playing && state.processingState == AudioProcessingState.ready;
      if (_ready && !wasReady) _sincePlay.reset();
      if (_ready) _sincePlay.start();
      if (!_ready) _clearLevel();
      _update();
    });
    _trackSubscription = audioHandler.mediaItem
        .map((item) => item?.id)
        .distinct()
        .listen((_) {
          _clearLevel();
          _update();
        });
    waveReading.addListener(_onReadingChanged);
  }

  void _onReadingChanged() {
    _stopReader();
    _update();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animating =
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
    _update();
  }

  void _clearLevel() {
    _level = null;
    _motion.beat = 0;
  }

  void _onLevel(AudioLevel level) {
    if (!_moving) return;
    if (_sincePlay.elapsed < _warmUp &&
        level.loud == 0 &&
        level.bands.every((band) => band == 0)) {
      return;
    }
    _level = level;
    _sinceLevel
      ..reset()
      ..start();
  }

  void _update() {
    if (_moving) {
      _releaseReader?.cancel();
      _releaseReader = null;
      if (_precise && _levels == null) {
        _expectLevels = true;
        _levels = AudioLevels.listen().listen(_onLevel);
        unawaited(
          AudioLevels.available.then((available) {
            if (mounted) _expectLevels = available;
          }),
        );
      }
      if (!_ticker.isActive) _ticker.start();
      return;
    }
    _clearLevel();
    // Paused but in view, the reader stays a moment, so a short pause does not
    // make the resume start it afresh; covered, it goes at once.
    if (_levels != null) {
      if (_animating) {
        _releaseReader ??= Timer(_readerGrace, _stopReader);
      } else {
        _stopReader();
      }
    }
    // Paused but in view, the bars go down rather than stay frozen mid-beat;
    // covered they simply stop where they are.
    if (_animating && !_motion.isQuiet) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      _rest();
    }
  }

  void _stopReader() {
    _releaseReader?.cancel();
    _releaseReader = null;
    _expectLevels = false;
    _clearLevel();
    unawaited(_levels?.cancel());
    _levels = null;
  }

  void _rest() {
    _ticker.stop();
    _last = Duration.zero;
    _due = 0;
  }

  void _tick(Duration elapsed) {
    if (elapsed.inMicroseconds < _due - _earlyMicroseconds) return;
    final dt = min((elapsed - _last).inMicroseconds / 1e6, 0.1);
    _last = elapsed;
    // Back on schedule if a frame came late, rather than catching up.
    _due = max(_due + _frameMicroseconds, elapsed.inMicroseconds);
    if (_level != null && _sinceLevel.elapsed > _staleAfter) _level = null;
    _motion.advance(
      dt,
      level: _level,
      rising:
          _ready &&
          !(_level == null && _expectLevels && _sincePlay.elapsed < _musicWait),
    );
    if (!_ready && _motion.isQuiet) _motion.settle();
    _repaint.value++;
    if (!_ready && _motion.isQuiet) _rest();
  }

  @override
  void dispose() {
    waveReading.removeListener(_onReadingChanged);
    _releaseReader?.cancel();
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
          heights: _motion.heights,
          repaint: _repaint,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );
}

/// The bars' motion, from 0 to 1 each: their own sway, crossed over to the
/// music when readings come, all eased so nothing jumps.
class _WaveMotion {
  static const bars = 9;

  /// Where the bars start and come to rest: no height at all, only the dots
  /// the painter keeps them from shrinking below.
  final heights = List<double>.filled(bars, 0);
  final _music = List<double>.filled(bars, 0);
  double _time = 0;
  double beat = 0;

  /// 0 in silence, 1 playing: the bars rise and fall with it over a moment,
  /// so a pause, a resume or a new song never jumps them.
  double _energy = 0;

  /// 0 for the bars' own motion, 1 for the music: they cross over, so the
  /// reading arriving does not shake the bars.
  double _blend = 0;

  bool get isQuiet => heights.every((height) => height < 0.004);

  void settle() => heights.fillRange(0, bars, 0);

  void advance(double dt, {required AudioLevel? level, required bool rising}) {
    _time += dt;
    beat = max(level?.onset ?? 0, beat * pow(0.02, dt).toDouble());
    _energy +=
        ((rising ? 1 : 0) - _energy) * (1 - exp(-(rising ? 9 : 12) * dt));
    _blend += ((level == null ? 0 : 1) - _blend) * (1 - exp(-8 * dt));
    for (var i = 0; i < bars; i++) {
      final reach = (i - (bars - 1) / 2).abs() / ((bars - 1) / 2);
      if (level != null) {
        final index = (reach * (AudioLevels.bandCount - 1)).round();
        final band = index < level.bands.length
            ? level.bands[index]
            : level.loud;
        _music[i] =
            0.08 +
            band * 0.62 * (1 - 0.2 * reach) +
            beat * 0.3 * pow(1 - reach, 2) +
            level.loud * 0.03 * sin(_time * 6 + i * 1.7);
      }
      final own =
          (0.3 +
              0.14 * sin(_time * 2.1 + i * 0.8) +
              0.08 * sin(_time * 3.3 - i * 1.2)) *
          (1 - 0.3 * reach);
      final target = _energy * (own + (_music[i] - own) * _blend);
      final rate = target > heights[i] ? 30.0 : 7.0;
      heights[i] += (target - heights[i]) * (1 - exp(-rate * dt));
    }
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
