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
import 'package:musify/utilities/platform_utils.dart';

/// Horizontal artwork browsing with desktop arrows and mouse dragging.
/// The ambient background belongs to the page, not individual artwork.
class GlowRow extends StatefulWidget {
  const GlowRow({
    super.key,
    required this.itemCount,
    required this.itemExtent,
    required this.itemBuilder,
  });

  final int itemCount;

  /// Width of each item, padding included.
  final double itemExtent;
  final IndexedWidgetBuilder itemBuilder;

  @override
  State<GlowRow> createState() => _GlowRowState();
}

class _GlowRowState extends State<GlowRow> {
  final _controller = ScrollController();

  /// Whether there is more to see before and after, for the desktop arrows.
  final _canScroll = ValueNotifier<(bool, bool)>((false, false));

  @override
  void dispose() {
    _controller.dispose();
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
            itemCount: widget.itemCount,
            itemBuilder: widget.itemBuilder,
          ),
        ),
      ),
    );

    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Stack(
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
                      alignment: AlignmentDirectional.centerStart,
                      icon: rtl
                          ? FluentIcons.chevron_right_24_regular
                          : FluentIcons.chevron_left_24_regular,
                      onPressed: () => _page(-1),
                    ),
                  if (canScroll.$2)
                    _ArrowButton(
                      alignment: AlignmentDirectional.centerEnd,
                      icon: rtl
                          ? FluentIcons.chevron_left_24_regular
                          : FluentIcons.chevron_right_24_regular,
                      onPressed: () => _page(1),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Sits in a [Stack] that covers the row.
class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.alignment,
    required this.icon,
    required this.onPressed,
  });

  final AlignmentGeometry alignment;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          // Not the floating chrome: a blur per arrow, repainted while the row
          // scrolls, is far more than a button over artwork needs.
          child: Material(
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.9),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            child: IconButton(icon: Icon(icon), onPressed: onPressed),
          ),
        ),
      ),
    );
  }
}

/// The phones' weighted carousel (3 : 2 : 1).
class GlowCarousel extends StatelessWidget {
  const GlowCarousel({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.onTap,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onTap;

  static const weights = [3, 2, 1];

  @override
  Widget build(BuildContext context) {
    return CarouselView.weighted(
      flexWeights: weights,
      itemSnapping: true,
      onTap: onTap,
      children: [for (var i = 0; i < itemCount; i++) itemBuilder(context, i)],
    );
  }
}
