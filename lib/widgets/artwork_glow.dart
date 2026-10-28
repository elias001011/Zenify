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

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/artwork_colors.dart';
import 'package:musify/services/settings_manager.dart';

/// Glow strength at the centre, by theme.
double artworkGlowStrength(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? 0.3 : 0.22;

// (1 - x²)³ from the centre (x = 0) to the edge (x = 1): no visible rim.
const _falloffStops = [0.0, 0.25, 0.5, 0.75, 1.0];
const _falloff = [1.0, 0.82, 0.42, 0.084, 0.0];

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
      colors: [for (final f in _falloff) color.withValues(alpha: alpha * f)],
      stops: _falloffStops,
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
  canvas
    ..drawCircle(Offset.zero, radius, paint)
    ..restore();
}

/// The glow colours of a set of artworks, by index. They ease from one set
/// to the next, and each fades in when its artwork's colour arrives.
class GlowColors {
  GlowColors(TickerProvider vsync)
    : _transition = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 1200),
        value: 1,
      );

  final AnimationController _transition;
  var _from = <int, Color>{};
  var _to = <int, Color>{};
  List<String?>? _sources;
  Color? _appColor;
  int _generation = 0;

  /// What a glow painter repaints on.
  Listenable get listenable => _transition;

  /// Indices that have a glow now or are easing out of one.
  Iterable<int> get indices => {..._from.keys, ..._to.keys};

  /// The colour of glow [index] now; its alpha carries the fade.
  Color? colorAt(int index) {
    final from = _from[index];
    final to = _to[index];
    if (from == null && to == null) return null;
    return Color.lerp(
      from ?? to!.withAlpha(0),
      to ?? from!.withAlpha(0),
      Curves.easeInOut.transform(_transition.value),
    );
  }

  /// Glows for [sources]; one without artwork, or without a colour found in
  /// it, glows in [appColor]. Known colours show at once the first time.
  void update(List<String?> sources, Color appColor) {
    if (appColor == _appColor && listEquals(sources, _sources)) return;
    final first = _sources == null;
    _sources = List.of(sources);
    _appColor = appColor;
    final generation = ++_generation;

    final next = <int, Color>{};
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      if (source == null || source.isEmpty) {
        next[i] = appColor;
      } else if (ArtworkColors.isCached(source)) {
        next[i] = ArtworkColors.cached(source) ?? appColor;
      } else {
        ArtworkColors.of(source).then((color) {
          if (generation == _generation) {
            _retarget({..._to, i: color ?? appColor});
          }
        });
      }
    }

    if (first) {
      _to = next;
    } else {
      _retarget(next);
    }
  }

  void _retarget(Map<int, Color> next) {
    _from = {
      for (final i in indices)
        if (colorAt(i) case final color? when color.a > 0) i: color,
    };
    _to = next;
    _transition.forward(from: 0);
  }

  void dispose() {
    _generation++;
    _transition.dispose();
  }
}

/// The page background for an artwork (or the app colour, without one),
/// when the dynamic background is on: a large soft ball of its colour from
/// the top, emptying into the page, and a fainter neighbouring hue below.
class PageGlow extends StatefulWidget {
  const PageGlow({super.key, required this.source});

  /// The artwork's network URL or file path.
  final String? source;

  @override
  State<PageGlow> createState() => _PageGlowState();
}

class _PageGlowState extends State<PageGlow>
    with SingleTickerProviderStateMixin {
  late final _colors = GlowColors(this);

  void _update() =>
      _colors.update([widget.source], Theme.of(context).colorScheme.primary);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(PageGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void dispose() {
    _colors.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: dynamicBackground,
      builder: (context, enabled, _) => !enabled
          ? const SizedBox.expand()
          : RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: _PageGlowPainter(
                  colors: _colors,
                  strength: artworkGlowStrength(context),
                ),
              ),
            ),
    );
  }
}

class _PageGlowPainter extends CustomPainter {
  _PageGlowPainter({required this.colors, required this.strength})
    : super(repaint: colors.listenable);

  final GlowColors colors;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final color = colors.colorAt(0);
    if (color == null || color.a == 0) return;
    final alpha = strength * color.a;
    final extent = max(size.width, size.height);

    // A neighbouring hue, as the second light of a stage.
    final hsl = HSLColor.fromColor(color);
    final second = hsl.withHue((hsl.hue + 28) % 360).toColor();
    paintArtworkGlow(
      canvas,
      Rect.fromCircle(
        center: Offset(size.width * 0.82, size.height * 0.78),
        radius: extent * 0.5,
      ),
      second,
      alpha * 0.55,
    );
    paintArtworkGlow(
      canvas,
      Rect.fromCenter(
        center: Offset(size.width * 0.42, size.height * 0.12),
        width: extent * 1.5,
        height: extent * 1.1,
      ),
      color,
      alpha,
    );
  }

  @override
  bool shouldRepaint(_PageGlowPainter oldDelegate) =>
      oldDelegate.strength != strength || oldDelegate.colors != colors;
}
