import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:musify/services/mix_analysis.dart';
import 'package:musify/services/mix_transition.dart';

/// Two waveforms, beat grids and the motor's actual volume curves on one
/// timeline. Dragging moves the recording under the transition markers.
class MixTimeline extends StatelessWidget {
  const MixTimeline({
    super.key,
    required this.cue,
    required this.tail,
    required this.head,
    this.onOutgoing,
    this.onIncoming,
    this.onSeek,
    this.playhead,
  });

  final MixCue cue;
  final MixInspection? tail;
  final MixInspection? head;
  final ValueChanged<double>? onOutgoing;
  final ValueChanged<double>? onIncoming;
  final ValueChanged<double>? onSeek;
  final double? playhead;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final colors = Theme.of(context).colorScheme;
      return GestureDetector(
        onTapUp: onSeek == null
            ? null
            : (event) => onSeek!(
                (event.localPosition.dx /
                            constraints.maxWidth *
                            (cue.length.inMilliseconds / 1000 + 10) -
                        5)
                    .clamp(-5.0, cue.length.inMilliseconds / 1000 - 0.35),
              ),
        onHorizontalDragUpdate: onOutgoing == null
            ? null
            : (event) {
                final seconds =
                    -event.delta.dx /
                    constraints.maxWidth *
                    (cue.length.inMilliseconds / 1000 + 10);
                (event.localPosition.dy < 100 ? onOutgoing : onIncoming)?.call(
                  seconds,
                );
              },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: CustomPaint(
            size: Size(constraints.maxWidth, 200),
            painter: _TimelinePainter(cue, tail, head, colors, playhead),
          ),
        ),
      );
    },
  );
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter(this.cue, this.tail, this.head, this.colors, this.playhead);
  final MixCue cue;
  final MixInspection? tail;
  final MixInspection? head;
  final ColorScheme colors;
  final double? playhead;

  @override
  void paint(Canvas canvas, Size size) {
    final length = cue.length.inMilliseconds.toDouble();
    final span = length + 10000;
    double x(double ms) => (ms + 5000) / span * size.width;
    canvas
      ..drawRect(
        Offset.zero & size,
        Paint()..color = colors.surfaceContainerHighest,
      )
      ..drawRect(
        Rect.fromLTRB(x(0), 0, x(length), size.height),
        Paint()..color = colors.primary.withValues(alpha: 0.08),
      );
    for (final incoming in [false, true]) {
      final inspection = incoming ? head : tail;
      final color = incoming ? colors.tertiary : colors.primary;
      final top = incoming ? size.height / 2 : 0.0;
      final center = top + size.height / 4;
      final sourceStart =
          (incoming ? cue.inStart : cue.outStart).inMilliseconds;
      canvas.drawLine(
        Offset(0, center),
        Offset(size.width, center),
        Paint()..color = color.withValues(alpha: 0.2),
      );
      if (inspection != null && inspection.wave.isNotEmpty) {
        final peak = max(0.01, inspection.wave.reduce(max));
        for (var i = 0; i < inspection.wave.length; i++) {
          final time =
              inspection.offset +
              (i + 0.5) * inspection.length / inspection.wave.length -
              sourceStart;
          if (incoming ? time < 0 : time > length) continue;
          final at = x(incoming ? time / cue.tempoRatio : time);
          if (at < 0 || at > size.width) continue;
          final height = inspection.wave[i] / peak * (size.height / 4 - 14);
          canvas.drawLine(
            Offset(at, center - height),
            Offset(at, center + height),
            Paint()
              ..color = color.withValues(alpha: 0.38)
              ..strokeWidth = max(1, size.width / inspection.wave.length),
          );
        }
        final edge = inspection.edge;
        if (edge.rhythmic) {
          final beatMs = 60000 / edge.bpm;
          final first = ((sourceStart - 5000 - edge.beatAt) / beatMs).ceil();
          final last = ((sourceStart + length + 5000 - edge.beatAt) / beatMs)
              .floor();
          for (var beat = first; beat <= last && beat < first + 400; beat++) {
            final time = edge.beatAt + beat * beatMs - sourceStart;
            if (incoming ? time < 0 : time > length) continue;
            canvas.drawLine(
              Offset(x(incoming ? time / cue.tempoRatio : time), top + 6),
              Offset(
                x(incoming ? time / cue.tempoRatio : time),
                top + size.height / 2 - 6,
              ),
              Paint()
                ..color = color.withValues(alpha: beat % 4 == 0 ? 0.35 : 0.15),
            );
          }
        }
      }
      final curve = Path();
      for (var i = 0; i <= 120; i++) {
        final t = i / 120;
        final frame = cue.frame(t);
        final gain = incoming ? frame.inGain : frame.outGain;
        final point = Offset(
          x(t * length),
          top + size.height / 2 - 10 - gain * (size.height / 2 - 20),
        );
        if (i == 0) {
          curve.moveTo(point.dx, point.dy);
        } else {
          curve.lineTo(point.dx, point.dy);
        }
      }
      final bass = Path();
      for (var i = 0; i <= 120; i++) {
        final frame = cue.frame(i / 120);
        final db = incoming ? frame.inBands.low : frame.outBands.low;
        final px = x(i / 120 * length);
        final py =
            top + size.height / 2 - 10 - (1 + db / 24) * (size.height / 2 - 20);
        if (i == 0) {
          bass.moveTo(px, py);
        } else {
          bass.lineTo(px, py);
        }
      }
      canvas
        ..drawPath(
          bass,
          Paint()
            ..color = colors.secondary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        )
        ..drawPath(
          curve,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
    }
    if (playhead != null) {
      final at = x(playhead! * 1000);
      canvas
        ..drawLine(
          Offset(at, 0),
          Offset(at, size.height),
          Paint()
            ..color = colors.onSurface
            ..strokeWidth = 2,
        )
        ..drawCircle(Offset(at, 8), 5, Paint()..color = colors.onSurface);
    }
    for (final ms in [0.0, length]) {
      canvas
        ..drawLine(
          Offset(x(ms), 0),
          Offset(x(ms), size.height),
          Paint()..color = colors.onSurface.withValues(alpha: 0.5),
        )
        ..drawCircle(Offset(x(ms), 7), 4, Paint()..color = colors.onSurface);
    }
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      Paint()..color = colors.outlineVariant,
    );
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) =>
      old.playhead != playhead ||
      old.cue != cue ||
      old.tail != tail ||
      old.head != head ||
      old.colors != colors;
}
