import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:musify/services/mix_analysis.dart';
import 'package:musify/services/mix_transition.dart';

/// The two songs' waveforms, one over the other, under the window of the
/// transition. Dragging a waveform moves that song under the window;
/// dragging an edge of the window makes the transition longer or shorter.
class MixTimeline extends StatefulWidget {
  const MixTimeline({
    super.key,
    required this.cue,
    required this.tail,
    required this.head,
    this.onOutgoing,
    this.onIncoming,
    this.onResize,
    this.onSeek,
    this.onDragEnd,
    this.playhead,
    this.play,
    this.length,
    this.outLabel,
    this.inLabel,
    this.outSkips = const [],
    this.inSkips = const [],
  });

  static const height = 232.0;

  /// Room above and below the waveforms for the two times.
  static const _gutter = 18.0;

  /// How much of each song is shown before and after the transition.
  static const _lead = 5000.0;

  final MixCue cue;
  final MixInspection? tail;
  final MixInspection? head;

  /// Seconds the outgoing or the incoming song was dragged by.
  final ValueChanged<double>? onOutgoing;
  final ValueChanged<double>? onIncoming;

  /// Seconds the start and the length of the transition were dragged by.
  final void Function(double start, double length)? onResize;
  final ValueChanged<double>? onSeek;

  /// A drag of a waveform or an edge is over.
  final VoidCallback? onDragEnd;
  final double? playhead;

  /// Shown in the middle of the window and at its foot.
  final Widget? play;
  final Widget? length;
  final String? outLabel;
  final String? inLabel;

  /// The stretches of each song that are skipped when it plays.
  final List<MixSkip> outSkips;
  final List<MixSkip> inSkips;

  @override
  State<MixTimeline> createState() => _MixTimelineState();
}

enum _Drag { outgoing, incoming, start, end }

class _MixTimelineState extends State<MixTimeline> {
  _Drag? _drag;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      final width = constraints.maxWidth;
      final length = widget.cue.length.inMilliseconds.toDouble();
      final span = length + MixTimeline._lead * 2;
      final left = MixTimeline._lead / span * width;
      final right = width - left;
      final label = theme.textTheme.labelSmall?.copyWith(
        color: colors.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: widget.onSeek == null
            ? null
            : (event) => widget.onSeek!(
                ((event.localPosition.dx / width * span - MixTimeline._lead) /
                        1000)
                    .clamp(-5.0, length / 1000 - 0.35),
              ),
        onHorizontalDragStart: (event) {
          final at = event.localPosition;
          _drag = widget.onResize != null && (at.dx - left).abs() < 22
              ? _Drag.start
              : widget.onResize != null && (at.dx - right).abs() < 22
              ? _Drag.end
              : at.dy < MixTimeline._gutter + MixTimeline.height / 2
              ? _Drag.outgoing
              : _Drag.incoming;
        },
        onHorizontalDragEnd: (_) {
          _drag = null;
          widget.onDragEnd?.call();
        },
        onHorizontalDragCancel: () {
          _drag = null;
          widget.onDragEnd?.call();
        },
        onHorizontalDragUpdate: (event) {
          final seconds = event.delta.dx / width * span / 1000;
          switch (_drag) {
            case _Drag.outgoing:
              widget.onOutgoing?.call(-seconds);
            case _Drag.incoming:
              widget.onIncoming?.call(-seconds);
            // The window stays centred, so an edge moves half of the change.
            case _Drag.start:
              widget.onResize?.call(seconds * 2, -seconds * 2);
            case _Drag.end:
              widget.onResize?.call(0, seconds * 2);
            case null:
          }
        },
        child: SizedBox(
          height: MixTimeline.height + MixTimeline._gutter * 2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                top: MixTimeline._gutter,
                bottom: MixTimeline._gutter,
                child: ClipRect(
                  child: CustomPaint(
                    painter: _TimelinePainter(
                      widget.cue,
                      widget.tail,
                      widget.head,
                      colors,
                      widget.playhead,
                      handles: widget.onResize != null,
                      outSkips: widget.outSkips,
                      inSkips: widget.inSkips,
                    ),
                  ),
                ),
              ),
              if (widget.outLabel != null)
                Positioned(
                  left: left + 4,
                  top: 1,
                  child: Text(widget.outLabel!, style: label),
                ),
              if (widget.inLabel != null)
                Positioned(
                  left: left + 4,
                  bottom: 1,
                  child: Text(widget.inLabel!, style: label),
                ),
              if (widget.play != null) widget.play!,
              if (widget.length != null)
                Positioned(bottom: 4, child: widget.length!),
            ],
          ),
        ),
      );
    },
  );
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(
    this.cue,
    this.tail,
    this.head,
    this.colors,
    this.playhead, {
    required this.handles,
    required this.outSkips,
    required this.inSkips,
  });
  final List<MixSkip> outSkips;
  final List<MixSkip> inSkips;
  final MixCue cue;
  final MixInspection? tail;
  final MixInspection? head;
  final ColorScheme colors;
  final double? playhead;
  final bool handles;

  @override
  void paint(Canvas canvas, Size size) {
    final length = cue.length.inMilliseconds.toDouble();
    final span = length + MixTimeline._lead * 2;
    double x(double ms) => (ms + MixTimeline._lead) / span * size.width;
    final lane = size.height / 2;
    final window = RRect.fromRectAndRadius(
      Rect.fromLTRB(x(0), 0, x(length), size.height),
      const Radius.circular(14),
    );
    canvas.drawRRect(
      window,
      Paint()..color = colors.onSurface.withValues(alpha: 0.08),
    );

    for (final incoming in [false, true]) {
      final inspection = incoming ? head : tail;
      final color = incoming ? colors.tertiary : colors.primary;
      final top = incoming ? lane : 0.0;
      final center = top + lane / 2;
      final ratio = incoming ? cue.tempoRatio : 1.0;
      final sourceStart =
          (incoming ? cue.inStart : cue.outStart).inMilliseconds;
      // The song's own time at a point of the timeline, and back.
      double source(double ms) => sourceStart + ms * ratio;
      double place(double sourceMs) => x((sourceMs - sourceStart) / ratio);

      // What is skipped when the song plays, struck through.
      for (final skip in incoming ? inSkips : outSkips) {
        final from = place(skip.start.toDouble()).clamp(0.0, size.width);
        final to = place(skip.end.toDouble()).clamp(0.0, size.width);
        if (to <= from) continue;
        canvas
          ..drawRect(
            Rect.fromLTRB(from, top + 6, to, top + lane - 6),
            Paint()..color = colors.error.withValues(alpha: 0.16),
          )
          ..drawLine(
            Offset(from, center),
            Offset(to, center),
            Paint()
              ..color = colors.error
              ..strokeWidth = 1.5,
          );
      }

      if (inspection == null || inspection.wave.isEmpty) {
        canvas.drawLine(
          Offset(0, center),
          Offset(size.width, center),
          Paint()..color = colors.onSurface.withValues(alpha: 0.2),
        );
      } else {
        final wave = inspection.wave;
        final peak = max(0.01, wave.reduce(max));
        final binMs = inspection.length / wave.length;
        final binWidth = binMs / ratio / span * size.width;
        // Bars narrower than this are joined, by the loudest of them.
        final step = max(1, (2.5 / binWidth).ceil());
        final first =
            ((source(-MixTimeline._lead) - inspection.offset) / binMs)
                .floor() ~/
            step *
            step;
        final last =
            ((source(length + MixTimeline._lead) - inspection.offset) / binMs)
                .ceil();
        final paint = Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = max(1.5, binWidth * step * 0.62);
        for (var i = max(0, first); i < min(wave.length, last); i += step) {
          var value = 0.0;
          for (var j = i; j < min(wave.length, i + step); j++) {
            value = max(value, wave[j]);
          }
          final time =
              (inspection.offset + (i + step / 2) * binMs - sourceStart) /
              ratio;
          // Dim where the song is not heard: gone already, or not in yet.
          final silent = incoming ? time < 0 : time > length;
          final inside = time >= 0 && time <= length;
          paint.color = colors.onSurface.withValues(
            alpha: silent
                ? 0.14
                : inside
                ? 0.8
                : 0.42,
          );
          final height = max(1, value / peak * (lane / 2 - 12));
          final at = x(time);
          canvas.drawLine(
            Offset(at, center - height),
            Offset(at, center + height),
            paint,
          );
        }
        final edge = inspection.edge;
        if (edge.rhythmic) {
          // The bars of each song, inside the window.
          final beatMs = 60000 / edge.bpm;
          final from = ((source(0) - edge.beatAt) / beatMs).ceil();
          final to = ((source(length) - edge.beatAt) / beatMs).floor();
          for (var beat = from; beat <= to && beat < from + 400; beat++) {
            if ((beat - edge.bar) % 4 != 0) continue;
            final at = place(edge.beatAt + beat * beatMs);
            canvas.drawLine(
              Offset(at, top + 4),
              Offset(at, top + lane - 4),
              Paint()..color = colors.onSurface.withValues(alpha: 0.22),
            );
          }
        }
      }

      // How loud this song is along the transition.
      final curve = Path();
      for (var i = 0; i <= 80; i++) {
        final t = i / 80;
        final frame = cue.frame(t);
        final gain = incoming ? frame.inGain : frame.outGain;
        final point = Offset(
          x(t * length),
          top + lane - 8 - gain.clamp(0.0, 1.0) * (lane - 16),
        );
        if (i == 0) {
          curve.moveTo(point.dx, point.dy);
        } else {
          curve.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        curve,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 2,
      );
    }

    canvas
      ..drawLine(
        Offset(x(0) + 8, lane),
        Offset(x(length) - 8, lane),
        Paint()..color = colors.onSurface.withValues(alpha: 0.18),
      )
      ..drawRRect(
        window,
        Paint()
          ..color = colors.onSurface.withValues(alpha: 0.38)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    if (handles) {
      for (final at in [x(0), x(length)]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(at, lane), width: 5, height: 34),
            const Radius.circular(3),
          ),
          Paint()..color = colors.onSurface,
        );
      }
    }
    if (playhead != null) {
      final at = x(playhead! * 1000);
      canvas.drawLine(
        Offset(at, 0),
        Offset(at, size.height),
        Paint()
          ..color = colors.primary
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      old.playhead != playhead ||
      old.cue != cue ||
      old.tail != tail ||
      old.head != head ||
      old.colors != colors ||
      old.handles != handles ||
      old.outSkips != outSkips ||
      old.inSkips != inSkips;
}
