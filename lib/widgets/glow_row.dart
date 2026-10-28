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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/artwork_colors.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/platform_utils.dart';
import 'package:musify/widgets/floating_surface.dart';

/// A horizontal row of artworks of the same size, with:
/// - the dynamic background: one layer behind the whole row paints every
///   glow, so they never tint a neighbour and scrolling repaints only it;
/// - previous / next buttons and mouse dragging on desktop.
class GlowRow extends StatefulWidget {
  const GlowRow({
    super.key,
    required this.sources,
    required this.itemExtent,
    required this.itemBuilder,
  });

  /// Artwork URL or file path for each item, in order.
  final List<String?> sources;

  /// Width of each item, padding included.
  final double itemExtent;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<GlowRow> createState() => _GlowRowState();
}

class _GlowRowState extends State<GlowRow> with SingleTickerProviderStateMixin {
  final _controller = ScrollController();
  final _colors = <int, Color>{};
  final _colorsChanged = ValueNotifier<int>(0);

  /// Whether there is more to see before and after, for the desktop arrows.
  final _canScroll = ValueNotifier<(bool, bool)>((false, false));
  late final _fadeIn = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _resolveColors();
  }

  @override
  void didUpdateWidget(GlowRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.sources, widget.sources)) {
      _colors.clear();
      _resolveColors();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _colorsChanged.dispose();
    _canScroll.dispose();
    _fadeIn.dispose();
    super.dispose();
  }

  void _resolveColors() {
    var allCached = true;
    for (var i = 0; i < widget.sources.length; i++) {
      final source = widget.sources[i];
      if (source == null || source.isEmpty) continue;
      if (ArtworkColors.isCached(source)) {
        final color = ArtworkColors.cached(source);
        if (color != null) _colors[i] = color;
        continue;
      }
      allCached = false;
      ArtworkColors.of(source).then((color) {
        if (!mounted || color == null) return;
        _colors[i] = color;
        _colorsChanged.value++;
        if (!_fadeIn.isAnimating && !_fadeIn.isCompleted) _fadeIn.forward();
      });
    }
    // Colours already known (coming back to the page) show without fading.
    if (allCached) _fadeIn.value = 1;
  }

  bool _onMetrics(ScrollMetrics metrics) {
    _canScroll.value = (
      metrics.pixels > metrics.minScrollExtent + 1,
      metrics.pixels < metrics.maxScrollExtent - 1,
    );
    return false;
  }

  void _page(int direction) {
    final position = _controller.position;
    final target =
        (position.pixels + direction * position.viewportDimension * 0.8).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    final list = ScrollConfiguration(
      // Mouse and trackpad can drag the row on desktop.
      behavior: ScrollConfiguration.of(context)
          .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (n) => _onMetrics(n.metrics),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) => _onMetrics(n.metrics),
          child: ListView.builder(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            itemExtent: widget.itemExtent,
            itemCount: widget.sources.length,
            itemBuilder: widget.itemBuilder,
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        // The glow reaches well past the row, above and below it.
        final reach = height * 0.6;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: -reach,
              bottom: -reach,
              child: ValueListenableBuilder<bool>(
                valueListenable: dynamicBackground,
                builder: (context, enabled, _) => !enabled
                    ? const SizedBox.shrink()
                    : IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _RowGlowPainter(
                              controller: _controller,
                              colors: _colors,
                              itemExtent: widget.itemExtent,
                              rowTop: reach,
                              rowHeight: height,
                              strength: dark ? 0.5 : 0.35,
                              fade: _fadeIn,
                              repaint: Listenable.merge([
                                _controller,
                                _colorsChanged,
                                _fadeIn,
                              ]),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            list,
            if (isDesktopPlatform)
              Positioned.fill(
                child: ValueListenableBuilder<(bool, bool)>(
                  valueListenable: _canScroll,
                  builder: (context, canScroll, _) => Stack(
                    children: [
                      if (canScroll.$1)
                        _ArrowButton(
                          alignment: Alignment.centerLeft,
                          icon: FluentIcons.chevron_left_24_regular,
                          onPressed: () => _page(-1),
                        ),
                      if (canScroll.$2)
                        _ArrowButton(
                          alignment: Alignment.centerRight,
                          icon: FluentIcons.chevron_right_24_regular,
                          onPressed: () => _page(1),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RowGlowPainter extends CustomPainter {
  _RowGlowPainter({
    required this.controller,
    required this.colors,
    required this.itemExtent,
    required this.rowTop,
    required this.rowHeight,
    required this.strength,
    required this.fade,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final ScrollController controller;
  final Map<int, Color> colors;
  final double itemExtent;
  final double rowTop;
  final double rowHeight;
  final double strength;
  final Animation<double> fade;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = controller.hasClients ? controller.offset : 0.0;
    final radius = rowHeight * 1.1;
    final centerY = rowTop + rowHeight / 2;
    final alpha = strength * fade.value;
    if (alpha <= 0) return;

    for (final entry in colors.entries) {
      final centerX = entry.key * itemExtent + itemExtent / 2 - offset;
      if (centerX < -radius || centerX > size.width + radius) continue;
      final center = Offset(centerX, centerY);
      final color = entry.value;
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.45),
            color.withValues(alpha: 0),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_RowGlowPainter oldDelegate) =>
      oldDelegate.strength != strength ||
      oldDelegate.itemExtent != itemExtent ||
      oldDelegate.rowHeight != rowHeight;
}

/// Sits in a [Stack] that covers the row.
class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.alignment,
    required this.icon,
    required this.onPressed,
  });

  final Alignment alignment;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: FloatingSurface(
            borderRadius: const BorderRadius.all(Radius.circular(20)),
            child: IconButton(icon: Icon(icon), onPressed: onPressed),
          ),
        ),
      ),
    );
  }
}
