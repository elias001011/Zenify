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

class _GlowRowState extends State<GlowRow>
    with TickerProviderStateMixin, GlowColorsHost {
  final _controller = ScrollController();
  late final _repaint = Listenable.merge([_controller, glowColors.listenable]);

  /// Whether there is more to see before and after, for the desktop arrows.
  final _canScroll = ValueNotifier<(bool, bool)>((false, false));

  @override
  List<String?> get glowSources => widget.sources;

  @override
  void dispose() {
    _controller.dispose();
    _canScroll.dispose();
    super.dispose();
  }

  Iterable<(int, double, double)> _slots(double width) sync* {
    final offset = _controller.hasClients ? _controller.offset : 0.0;
    final extent = widget.itemExtent;
    for (final index in glowColors.indices) {
      // Glows spread past their artwork, so neighbours out of view count.
      final center = index * extent + extent / 2 - offset;
      if (center > -extent * 1.5 && center < width + extent * 1.5) {
        yield (index, center, extent);
      }
    }
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

    return _RowGlow(
      colors: glowColors,
      repaint: _repaint,
      slots: _slots,
      child: Stack(
        children: [
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
      ),
    );
  }
}

/// Where each artwork of a row sits: its index, horizontal centre and width,
/// for a row [width] wide. Only artworks in view need a slot.
typedef GlowSlots = Iterable<(int, double, double)> Function(double width);

/// Paints the glows of a row's artworks behind [child], reaching well past
/// the row above and below, in one layer that scrolling repaints alone.
class _RowGlow extends StatelessWidget {
  const _RowGlow({
    required this.colors,
    required this.repaint,
    required this.slots,
    required this.child,
  });

  final GlowColors colors;
  final Listenable repaint;
  final GlowSlots slots;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
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
                              colors: colors,
                              slots: slots,
                              rowTop: reach,
                              rowHeight: height,
                              strength: artworkGlowStrength(context),
                              repaint: repaint,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            child,
          ],
        );
      },
    );
  }
}

class _RowGlowPainter extends CustomPainter {
  _RowGlowPainter({
    required this.colors,
    required this.slots,
    required this.rowTop,
    required this.rowHeight,
    required this.strength,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final GlowColors colors;
  final GlowSlots slots;
  final double rowTop;
  final double rowHeight;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    final reveal = colors.reveal;
    if (reveal <= 0) return;
    final grow = colors.grow;
    final centerY = rowTop + rowHeight / 2;
    // Glows fade out as they reach the row's ends.
    final edge = size.width * 0.08;

    for (final (index, centerX, width) in slots(size.width)) {
      final color = colors.colorAt(index);
      final fade = (min(centerX, size.width - centerX) / edge).clamp(0.0, 1.0);
      if (color == null || color.a == 0 || width <= 0 || fade == 0) continue;
      // Proportional to the artwork, and wide and low enough that
      // neighbouring glows merge into one soft band.
      final hsl = HSLColor.fromColor(color);
      paintArtworkGlow(
        canvas,
        Rect.fromCenter(
          center: Offset(centerX, centerY),
          width: width * 2.6 * grow,
          height: min(rowHeight * 2.1, width * 2.1) * grow,
        ),
        hsl.withSaturation(hsl.saturation * 0.8).toColor(),
        strength * 1.5 * color.a * reveal * fade,
      );
    }
  }

  @override
  bool shouldRepaint(_RowGlowPainter oldDelegate) =>
      oldDelegate.strength != strength ||
      oldDelegate.colors != colors ||
      oldDelegate.slots != slots ||
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

/// The phones' weighted carousel (3 : 2 : 1), with a glow under each
/// artwork that follows it as it grows and shrinks.
class GlowCarousel extends StatefulWidget {
  const GlowCarousel({
    super.key,
    required this.sources,
    required this.itemBuilder,
    required this.onTap,
  });

  /// Artwork URL or file path for each item, in order.
  final List<String?> sources;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onTap;

  static const weights = [3, 2, 1];

  @override
  State<GlowCarousel> createState() => _GlowCarouselState();
}

class _GlowCarouselState extends State<GlowCarousel>
    with TickerProviderStateMixin, GlowColorsHost {
  final _controller = CarouselController();
  late final _repaint = Listenable.merge([_controller, glowColors.listenable]);

  @override
  List<String?> get glowSources => widget.sources;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The visible items as the carousel lays them out: the leading one gives
  /// up its room as it scrolls away and the others grow into it.
  Iterable<(int, double, double)> _slots(double width) sync* {
    const weights = GlowCarousel.weights;
    final unit = width / weights.reduce((a, b) => a + b);
    final leadExtent = weights.first * unit;
    if (leadExtent <= 0) return;
    final offset = _controller.hasClients ? _controller.offset : 0.0;
    final lead = (offset / leadExtent).floor();
    final progress = offset / leadExtent - lead;

    var start = 0.0;
    for (var i = 0; i <= weights.length; i++) {
      final index = lead + i;
      final extent = i == 0
          ? leadExtent * (1 - progress)
          : i < weights.length
          ? unit * weights[i] +
                (weights[i - 1] - weights[i]) /
                    weights.first *
                    progress *
                    leadExtent
          : width - start;
      if (index >= 0 && index < widget.sources.length && extent > 0) {
        yield (index, start + extent / 2, extent);
      }
      start += extent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _RowGlow(
      colors: glowColors,
      repaint: _repaint,
      slots: _slots,
      child: CarouselView.weighted(
        controller: _controller,
        flexWeights: GlowCarousel.weights,
        itemSnapping: true,
        onTap: widget.onTap,
        children: [
          for (var i = 0; i < widget.sources.length; i++)
            widget.itemBuilder(context, i),
        ],
      ),
    );
  }
}
