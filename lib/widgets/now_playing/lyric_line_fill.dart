import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/motion.dart';

/// Fills wrapped verses in reading order, one visual line at a time.
class LyricLineFill extends ImplicitlyAnimatedWidget {
  const LyricLineFill({
    super.key,
    required this.text,
    required this.style,
    required this.progress,
    this.emphasis = 1,
    this.baseOpacity = 0.38,
    this.textAlign = TextAlign.start,
    super.duration = Motion.short,
  });

  final String text;
  final TextStyle style;
  final double progress;
  final double emphasis;
  final double baseOpacity;
  final TextAlign textAlign;

  @override
  ImplicitlyAnimatedWidgetState<LyricLineFill> createState() =>
      _LyricLineFillState();
}

class _LyricLineFillState extends ImplicitlyAnimatedWidgetState<LyricLineFill> {
  Tween<double>? _progress;
  Tween<double>? _emphasis;
  final _painter = TextPainter();

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }

  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _progress = visitor(
      _progress,
      widget.progress,
      (value) => Tween<double>(begin: value as double),
    ) as Tween<double>?;
    _emphasis = visitor(
      _emphasis,
      widget.emphasis,
      (value) => Tween<double>(begin: value as double),
    ) as Tween<double>?;
  }

  @override
  Widget build(BuildContext context) {
    final defaults = DefaultTextStyle.of(context);
    final style = defaults.style.merge(widget.style);
    final paintStyle = style.copyWith(
      fontWeight: MediaQuery.boldTextOf(context)
          ? FontWeight.bold
          : style.fontWeight,
      height:
          MediaQuery.maybeLineHeightScaleFactorOverrideOf(context) ??
          style.height,
      letterSpacing:
          MediaQuery.maybeLetterSpacingOverrideOf(context) ??
          style.letterSpacing,
      wordSpacing:
          MediaQuery.maybeWordSpacingOverrideOf(context) ?? style.wordSpacing,
    );
    _painter
      ..text = TextSpan(text: widget.text, style: paintStyle)
      ..textHeightBehavior =
          defaults.textHeightBehavior ??
          DefaultTextHeightBehavior.maybeOf(context)
      ..textWidthBasis = defaults.textWidthBasis
      ..maxLines = defaults.maxLines
      ..textAlign = widget.textAlign
      ..textDirection = Directionality.of(context)
      ..textScaler = MediaQuery.textScalerOf(context)
      ..locale = Localizations.maybeLocaleOf(context);
    return RepaintBoundary(
      child: CustomPaint(
        foregroundPainter: _LineFillPainter(
          painter: _painter,
          progress: animation.drive(_progress!),
          emphasis: animation.drive(_emphasis!),
          repaint: animation,
        ),
        child: Text(
          widget.text,
          textAlign: widget.textAlign,
          style: style.copyWith(
            color: style.color!.withValues(alpha: widget.baseOpacity),
          ),
        ),
      ),
    );
  }
}

class _LineFillPainter extends CustomPainter {
  _LineFillPainter({
    required this.painter,
    required this.progress,
    required this.emphasis,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final TextPainter painter;
  final Animation<double> progress;
  final Animation<double> emphasis;

  @override
  void paint(Canvas canvas, Size size) {
    if (emphasis.value <= 0 || progress.value <= 0 || size.isEmpty) return;
    // Match the child's tight paragraph width, including centered wrapped text.
    painter.layout(minWidth: size.width, maxWidth: size.width);
    final lines = painter.computeLineMetrics();
    var remaining =
        lines.fold<double>(0, (sum, line) => sum + line.width) *
        progress.value.clamp(0.0, 1.0);
    final bounds = Offset.zero & size;
    canvas
      ..saveLayer(
        bounds,
        Paint()
          ..color = Colors.white.withValues(
            alpha: emphasis.value.clamp(0.0, 1.0),
          ),
      )
      ..clipRect(bounds);
    painter.paint(canvas, Offset.zero);
    final unfilled = Path();
    for (final line in lines) {
      final row = Rect.fromLTWH(
        0,
        line.baseline - line.ascent,
        size.width,
        line.height,
      );
      if (remaining <= 0) {
        unfilled.addRect(row);
      } else if (remaining < line.width && line.width > 0) {
        final edge = remaining / line.width;
        final feather = math.min(10.0 / line.width, 0.12);
        final rtl = painter.textDirection == TextDirection.rtl;
        final shader =
            LinearGradient(
              begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
              end: rtl ? Alignment.centerLeft : Alignment.centerRight,
              colors: const [
                Colors.transparent,
                Colors.transparent,
                Colors.white,
                Colors.white,
              ],
              stops: [
                0,
                (edge - feather).clamp(0.0, 1.0),
                (edge + feather).clamp(0.0, 1.0),
                1,
              ],
            ).createShader(
              Rect.fromLTWH(line.left, row.top, line.width, row.height),
            );
        canvas.drawRect(
          row,
          Paint()
            ..shader = shader
            ..blendMode = BlendMode.dstOut,
        );
      }
      remaining -= line.width;
    }
    canvas
      ..drawPath(
        unfilled,
        Paint()
          ..color = Colors.white
          ..blendMode = BlendMode.dstOut,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_LineFillPainter oldDelegate) => true;
}
