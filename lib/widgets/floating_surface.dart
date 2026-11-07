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

import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:musify/services/settings_manager.dart';

/// How opaque the floating chrome is under each [FloatingEffect]. It sits over
/// scrolling text, so the simple translucency keeps most of its colour (music
/// lists, over the page's glow only, can afford far less); the blur is what
/// lets the blurred one show more of what is behind.
double floatingOpacity(FloatingEffect effect, {required bool dark}) =>
    switch (effect) {
      FloatingEffect.solid => 1,
      FloatingEffect.translucent => dark ? 0.9 : 0.92,
      FloatingEffect.blurred => dark ? 0.5 : 0.6,
    };

/// The rounded surface every floating element (top island, bottom dock,
/// desktop rail, mini player) sits on, so they share one look.
///
/// [floatingEffect] decides how much of the content behind shows through.
class FloatingSurface extends StatefulWidget {
  const FloatingSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.padding = EdgeInsets.zero,
    this.grouped = false,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  /// Shares the backdrop read of the nearest [BackdropGroup]. Only for
  /// surfaces painted over everything else that never overlap each other
  /// (dock, rail, mini player; the player's bars): the group reads the
  /// backdrop once, at its first surface, so anything painted after that one
  /// would be missing behind the rest.
  final bool grouped;

  /// Shared window-edge spacing for the island, rail and dock.
  static const edgeMargin = 12.0;

  @override
  State<FloatingSurface> createState() => _FloatingSurfaceState();
}

class _FloatingSurfaceState extends State<FloatingSurface> {
  static final _blurFilter = ImageFilter.blur(sigmaX: 12, sigmaY: 12);

  /// Moves the content, with its state (the mini player's animations), when
  /// the blur is added or taken away around it, so solid and translucent
  /// surfaces need no filter or clip of their own.
  final _contentKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FloatingEffect>(
      valueListenable: floatingEffect,
      builder: (context, effect, _) => _build(context, effect),
    );
  }

  Widget _build(BuildContext context, FloatingEffect effect) {
    final colorScheme = Theme.of(context).colorScheme;
    final dark = colorScheme.brightness == Brightness.dark;
    final color = colorScheme.surfaceContainer.withValues(
      alpha: floatingOpacity(effect, dark: dark),
    );
    final borderRadius = widget.borderRadius;

    final Widget surface = Material(
      key: _contentKey,
      color: color,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        // The translucent surface swaps the plain border for light on its
        // edge; the child stays where it is, whatever the effect.
        decoration: effect == FloatingEffect.translucent
            ? _GlassEdge(borderRadius: borderRadius, dark: dark)
            : BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 0.8,
                ),
              ),
        child: Padding(padding: widget.padding, child: widget.child),
      ),
    );

    switch (effect) {
      case FloatingEffect.blurred:
        return ClipRRect(
          borderRadius: borderRadius,
          child: widget.grouped
              ? BackdropFilter.grouped(filter: _blurFilter, child: surface)
              : BackdropFilter(filter: _blurFilter, child: surface),
        );
      // A shadow under a see-through surface would darken what shows through.
      case FloatingEffect.translucent:
        return surface;
      case FloatingEffect.solid:
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.5 : 0.12),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: surface,
        );
    }
  }
}

/// The light the translucent surface catches, drawn over its fill: a faint
/// sheen fading in from the top and a one pixel rim, brightest at the
/// top-left and dim toward the bottom-right. Plain paint, so it costs no
/// layer and reads nothing from behind the surface.
class _GlassEdge extends Decoration {
  const _GlassEdge({required this.borderRadius, required this.dark});

  final BorderRadius borderRadius;
  final bool dark;

  @override
  bool hitTest(Size size, Offset position, {TextDirection? textDirection}) =>
      borderRadius.toRRect(Offset.zero & size).contains(position);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _GlassEdgePainter(this);

  @override
  bool operator ==(Object other) =>
      other is _GlassEdge &&
      other.borderRadius == borderRadius &&
      other.dark == dark;

  @override
  int get hashCode => Object.hash(borderRadius, dark);
}

class _GlassEdgePainter extends BoxPainter {
  _GlassEdgePainter(this._edge);

  final _GlassEdge _edge;

  // The shaders only change with the surface's rect, not with every frame.
  Rect? _rect;
  final _sheen = Paint();
  final _rim = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  final _hairline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.6
    ..color = Colors.black.withValues(alpha: 0.07);

  static Color _white(double alpha) => Colors.white.withValues(alpha: alpha);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final rect = offset & configuration.size!;
    final dark = _edge.dark;
    if (rect != _rect) {
      _rect = rect;
      _sheen.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [_white(dark ? 0.1 : 0.16), _white(0)],
      ).createShader(rect);
      _rim.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _white(dark ? 0.55 : 0.95),
          _white(dark ? 0.08 : 0.25),
          _white(dark ? 0.03 : 0.15),
          _white(dark ? 0.26 : 0.7),
        ],
        stops: const [0, 0.35, 0.65, 1],
      ).createShader(rect);
    }
    final shape = _edge.borderRadius.toRRect(rect);
    canvas.drawRRect(shape, _sheen);
    // On a light page the white rim alone would vanish.
    if (!dark) canvas.drawRRect(shape, _hairline);
    canvas.drawRRect(shape.deflate(0.5), _rim);
  }
}
