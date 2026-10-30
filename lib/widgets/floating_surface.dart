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
  static final _blurFilter = ImageFilter.blur(sigmaX: 18, sigmaY: 18);

  /// Moves the content, with its state (the mini player's audio reader and
  /// animations), when the blur is added or taken away around it, so solid
  /// and translucent surfaces need no filter or clip of their own.
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
    final base = colorScheme.surfaceContainer;
    final color = switch (effect) {
      FloatingEffect.solid => base,
      FloatingEffect.translucent => base.withValues(alpha: dark ? 0.78 : 0.82),
      FloatingEffect.blurred => base.withValues(alpha: dark ? 0.55 : 0.6),
    };
    final borderRadius = widget.borderRadius;

    final Widget surface = Material(
      key: _contentKey,
      color: color,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
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
