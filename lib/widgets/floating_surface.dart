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
class FloatingSurface extends StatelessWidget {
  const FloatingSurface({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  static const _blurSigma = 18.0;

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

    Widget surface = Material(
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
        child: Padding(padding: padding, child: child),
      ),
    );

    if (effect == FloatingEffect.blurred) {
      surface = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: _blurSigma, sigmaY: _blurSigma),
          child: surface,
        ),
      );
    }

    // A shadow under a see-through surface would darken what shows through.
    if (effect != FloatingEffect.solid) return surface;
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
