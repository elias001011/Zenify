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

/// Spreads the colour of an artwork behind it into the page background, when
/// the dynamic background is on. The glow fades in once the colour is known.
class ArtworkGlow extends StatefulWidget {
  const ArtworkGlow({
    super.key,
    required this.source,
    required this.child,
    this.spread = 40,
  });

  /// The artwork's network URL or file path.
  final String? source;
  final Widget child;

  /// How far the glow reaches past the artwork on each side.
  final double spread;

  @override
  State<ArtworkGlow> createState() => _ArtworkGlowState();
}

class _ArtworkGlowState extends State<ArtworkGlow> {
  Color? _color;
  bool _animate = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(ArtworkGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _resolve();
  }

  void _resolve() {
    final source = widget.source;
    if (source == null || source.isEmpty) {
      _color = null;
      return;
    }
    if (ArtworkColors.isCached(source)) {
      // Known colours show at once, e.g. when scrolling back.
      _color = ArtworkColors.cached(source);
      _animate = false;
      return;
    }
    ArtworkColors.of(source).then((color) {
      if (!mounted || widget.source != source) return;
      setState(() {
        _color = color;
        _animate = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: dynamicBackground,
      builder: (context, enabled, child) {
        final color = _color;
        if (!enabled || color == null) return child!;
        final dark = Theme.of(context).brightness == Brightness.dark;
        final glow = DecoratedBox(
          decoration: BoxDecoration(
            // Strong under the artwork, falling off fast past its edge, so
            // a neighbour's glow barely tints the next artwork.
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: dark ? 0.45 : 0.32),
                color.withValues(alpha: dark ? 0.18 : 0.12),
                color.withValues(alpha: 0),
              ],
              stops: const [0.45, 0.72, 1],
            ),
          ),
        );

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -widget.spread,
              top: -widget.spread,
              right: -widget.spread,
              bottom: -widget.spread,
              child: IgnorePointer(
                child: _animate
                    ? TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 900),
                        curve: Curves.easeOut,
                        builder: (context, value, glow) =>
                            Opacity(opacity: value, child: glow),
                        child: glow,
                      )
                    : glow,
              ),
            ),
            child!,
          ],
        );
      },
      child: widget.child,
    );
  }
}
