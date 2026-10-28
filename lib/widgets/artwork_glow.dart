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
  if (bounds.isEmpty || alpha <= 0) return;
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
///
/// The first colours also open [reveal]: the glow expanding into the page,
/// once per widget, so it plays when a page or the player opens and never
/// again for a song or playlist change.
class GlowColors {
  GlowColors(TickerProvider vsync)
    : _transition = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 1200),
        value: 1,
      ),
      _reveal = AnimationController(
        vsync: vsync,
        duration: const Duration(milliseconds: 1400),
      );

  final AnimationController _transition;
  final AnimationController _reveal;
  late final Listenable listenable = Listenable.merge([_transition, _reveal]);
  var _from = <int, Color>{};
  var _to = <int, Color>{};
  List<String?>? _sources;
  Color? _appColor;
  int _generation = 0;

  /// Indices that have a glow now or are easing out of one.
  Iterable<int> get indices => {..._from.keys, ..._to.keys};

  /// 0 to 1 while the glow first expands; painters fade it in with this.
  double get reveal => Curves.easeOutCubic.transform(_reveal.value);

  /// The glow's size against its full size while it expands.
  double get grow => 0.4 + 0.6 * reveal;

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
  /// it, glows in [appColor]. Cached colours also fade in on a newly opened page.
  void update(List<String?> sources, Color appColor) {
    if (appColor == _appColor && listEquals(sources, _sources)) return;
    _sources = List.of(sources);
    _appColor = appColor;
    final generation = ++_generation;

    final next = <int, Color>{};
    final pending = <Future<(int, Color?)>>[];
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      if (source == null || source.isEmpty) {
        next[i] = appColor;
      } else if (ArtworkColors.isCached(source)) {
        next[i] = ArtworkColors.cached(source) ?? appColor;
      } else {
        // Until its colour is read, a glow keeps the one it has, so a new
        // song doesn't dip to dark first.
        if (_to[i] case final current?) next[i] = current;
        pending.add(ArtworkColors.of(source).then((color) => (i, color)));
      }
    }
    _retarget(next);

    // Colours still to read arrive in batches, at most one transition per
    // 150 ms, so neither a slow artwork nor many quick ones hold the rest.
    final arrived = <int, Color>{};
    Timer? flush;
    for (final read in pending) {
      read.then((found) {
        if (generation != _generation) return;
        arrived[found.$1] = found.$2 ?? appColor;
        flush ??= Timer(const Duration(milliseconds: 150), () {
          flush = null;
          if (generation != _generation || arrived.isEmpty) return;
          _retarget({..._to, ...arrived});
          arrived.clear();
        });
      });
    }
  }

  void _retarget(Map<int, Color> next) {
    _from = {
      for (final i in indices)
        if (colorAt(i) case final color? when color.a > 0) i: color,
    };
    _to = next;
    _transition.forward(from: 0);
    if (next.isNotEmpty && _reveal.isDismissed) _reveal.forward();
  }

  void dispose() {
    _generation++;
    _transition.dispose();
    _reveal.dispose();
  }
}

/// Keeps a widget's [GlowColors] in step with [glowSources] and the app
/// colour, and disposes them with it.
mixin GlowColorsHost<T extends StatefulWidget> on TickerProviderStateMixin<T> {
  late final glowColors = GlowColors(this);

  /// The artworks to glow for, in order.
  List<String?> get glowSources;

  void _updateGlow() =>
      glowColors.update(glowSources, Theme.of(context).colorScheme.primary);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateGlow();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateGlow();
  }

  @override
  void dispose() {
    glowColors.dispose();
    super.dispose();
  }
}

/// The page background for an artwork (or the app colour, without one),
/// when the dynamic background is on: a large light of its colour from the
/// top, centred on the content (pages put their artwork there), emptying into
/// the page, and a fainter neighbouring hue low on one side. Both are circles
/// sized by the page, so they keep their shape on a tall phone as on a wide
/// window, and they reach under the desktop rail, which floats over them.
class PageGlow extends StatefulWidget {
  const PageGlow({super.key, required this.source});

  /// The artwork's network URL or file path.
  final String? source;

  @override
  State<PageGlow> createState() => _PageGlowState();
}

class _PageGlowState extends State<PageGlow>
    with TickerProviderStateMixin, GlowColorsHost {
  @override
  List<String?> get glowSources => [widget.source];

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
                  colors: glowColors,
                  strength: artworkGlowStrength(context),
                  contentLeft: MediaQuery.paddingOf(context).left,
                ),
              ),
            ),
    );
  }
}

class _PageGlowPainter extends CustomPainter {
  _PageGlowPainter({
    required this.colors,
    required this.strength,
    required this.contentLeft,
  }) : super(repaint: colors.listenable);

  final GlowColors colors;
  final double strength;

  /// Where the content starts, past the desktop rail.
  final double contentLeft;

  @override
  void paint(Canvas canvas, Size size) {
    final color = colors.colorAt(0);
    if (color == null || color.a == 0) return;
    final reveal = colors.reveal;
    final alpha = strength * color.a * reveal;
    if (alpha <= 0) return;
    final reach = size.shortestSide + size.longestSide * 0.35;
    final grow = colors.grow;

    // A neighbouring hue, as the second light of a stage.
    final hsl = HSLColor.fromColor(color);
    paintArtworkGlow(
      canvas,
      Rect.fromCircle(
        center: Offset(size.width * 0.85, size.height * 0.82),
        radius: reach * 0.48 * grow,
      ),
      hsl.withHue((hsl.hue + 28) % 360).toColor(),
      alpha * 0.5,
    );
    paintArtworkGlow(
      canvas,
      Rect.fromCircle(
        center: Offset((contentLeft + size.width) / 2, 0),
        radius: reach * 0.85 * grow,
      ),
      color,
      alpha,
    );
  }

  @override
  bool shouldRepaint(_PageGlowPainter oldDelegate) =>
      oldDelegate.strength != strength ||
      oldDelegate.colors != colors ||
      oldDelegate.contentLeft != contentLeft;
}
