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
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/platform_utils.dart';
import 'package:musify/widgets/artwork_glow.dart';
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
  late final _colors = GlowColors(this);
  late final _repaint = Listenable.merge([_controller, _colors.listenable]);

  /// Whether there is more to see before and after, for the desktop arrows.
  final _canScroll = ValueNotifier<(bool, bool)>((false, false));

  void _update() =>
      _colors.update(widget.sources, Theme.of(context).colorScheme.primary);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(GlowRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  @override
  void dispose() {
    _controller.dispose();
    _colors.dispose();
    _canScroll.dispose();
    super.dispose();
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
        final reach = height * 0.55;

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
                              strength: artworkGlowStrength(context),
                              repaint: _repaint,
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
    required Listenable repaint,
  }) : super(repaint: repaint);

  final ScrollController controller;
  final GlowColors colors;
  final double itemExtent;
  final double rowTop;
  final double rowHeight;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final offset = controller.hasClients ? controller.offset : 0.0;
    final radius = rowHeight * 1.05;
    final centerY = rowTop + rowHeight / 2;

    for (final index in colors.indices) {
      final centerX = index * itemExtent + itemExtent / 2 - offset;
      if (centerX < -radius || centerX > size.width + radius) continue;
      final color = colors.colorAt(index);
      if (color == null || color.a == 0) continue;
      paintArtworkGlow(
        canvas,
        Rect.fromCircle(center: Offset(centerX, centerY), radius: radius),
        color,
        strength * color.a,
      );
    }
  }

  @override
  bool shouldRepaint(_RowGlowPainter oldDelegate) =>
      oldDelegate.strength != strength ||
      oldDelegate.colors != colors ||
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
