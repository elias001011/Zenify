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

import 'package:material_ui/material_ui.dart';
import 'package:musify/services/artwork_colors.dart';
import 'package:musify/services/settings_manager.dart';

/// Glow strength at the centre, by theme.
double artworkGlowStrength(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? 0.5 : 0.35;

/// Paints one soft glow filling the oval [bounds]: the look of the dynamic
/// background, shared by every glow so they all match.
void paintArtworkGlow(Canvas canvas, Rect bounds, Color color, double alpha) {
  final radius = bounds.height / 2;
  canvas
    ..save()
    ..translate(bounds.center.dx, bounds.center.dy)
    ..scale(bounds.width / bounds.height, 1);
  final paint = Paint()
    ..shader = RadialGradient(
      colors: [
        color.withValues(alpha: alpha),
        color.withValues(alpha: alpha * 0.45),
        color.withValues(alpha: 0),
      ],
      stops: const [0, 0.5, 1],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
  canvas
    ..drawCircle(Offset.zero, radius, paint)
    ..restore();
}

/// Resolves artwork colours for glows and fades them in when they arrive.
/// Colours already known (coming back to a page) show at once.
mixin ArtworkGlowColors<T extends StatefulWidget>
    on SingleTickerProviderStateMixin<T> {
  /// Glow colour by index; null glows in the app colour (no artwork, or no
  /// colour found in it). Missing while still resolving.
  final glowColors = <int, Color?>{};
  final _colorsChanged = ValueNotifier<int>(0);
  late final _fadeIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  int _generation = 0;

  /// 0 to 1, for the painter's alpha.
  Animation<double> get glowFade => _fadeIn;

  /// What a glow painter repaints on.
  late final Listenable glowRepaint = Listenable.merge([
    _fadeIn,
    _colorsChanged,
  ]);

  void resolveGlowColors(List<String?> sources) {
    final generation = ++_generation;
    glowColors.clear();
    var allCached = true;
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      if (source == null || source.isEmpty) {
        glowColors[i] = null;
        continue;
      }
      if (ArtworkColors.isCached(source)) {
        glowColors[i] = ArtworkColors.cached(source);
        continue;
      }
      allCached = false;
      ArtworkColors.of(source).then((color) {
        if (!mounted || generation != _generation) return;
        glowColors[i] = color;
        _colorsChanged.value++;
        if (!_fadeIn.isAnimating && !_fadeIn.isCompleted) _fadeIn.forward();
      });
    }
    if (allCached) _fadeIn.value = 1;
    _colorsChanged.value++;
  }

  @override
  void dispose() {
    _colorsChanged.dispose();
    _fadeIn.dispose();
    super.dispose();
  }
}

/// A wide glow of an artwork's colour (or the app colour, without one)
/// behind [child], reaching past it into the page, when the dynamic
/// background is on. Used by page headers.
class ArtworkGlow extends StatefulWidget {
  const ArtworkGlow({super.key, required this.source, required this.child});

  /// The artwork's network URL or file path.
  final String? source;
  final Widget child;

  @override
  State<ArtworkGlow> createState() => _ArtworkGlowState();
}

class _ArtworkGlowState extends State<ArtworkGlow>
    with SingleTickerProviderStateMixin, ArtworkGlowColors {
  @override
  void initState() {
    super.initState();
    resolveGlowColors([widget.source]);
  }

  @override
  void didUpdateWidget(ArtworkGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) resolveGlowColors([widget.source]);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: dynamicBackground,
      builder: (context, enabled, child) => !enabled
          ? child!
          : CustomPaint(
              painter: _GlowPainter(
                colors: glowColors,
                appColor: Theme.of(context).colorScheme.primary,
                fade: glowFade,
                strength: artworkGlowStrength(context),
                repaint: glowRepaint,
              ),
              child: child,
            ),
      child: widget.child,
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({
    required this.colors,
    required this.appColor,
    required this.fade,
    required this.strength,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final Map<int, Color?> colors;
  final Color appColor;
  final Animation<double> fade;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = strength * fade.value;
    if (!colors.containsKey(0) || alpha <= 0) return;
    final color = colors[0] ?? appColor;
    // Wider than tall and well past the child, so it reads as background.
    final bounds = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: (size.width * 1.2).clamp(0, size.height * 5),
      height: size.height * 2.4,
    );
    paintArtworkGlow(canvas, bounds, color, alpha);
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) =>
      oldDelegate.strength != strength || oldDelegate.appColor != appColor;
}
