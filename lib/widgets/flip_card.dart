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

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

enum RotateSide { right, left, top, bottom }

/// Shows [frontWidget] or, when [flipped], [backWidget], turning round like
/// a card between them (the player's artwork flip from the original Musify).
class FlipCard extends StatefulWidget {
  const FlipCard({
    super.key,
    required this.frontWidget,
    required this.backWidget,
    required this.flipped,
    this.rotateSide = RotateSide.right,
    this.animationDuration = const Duration(milliseconds: 800),
  });

  final Widget frontWidget;
  final Widget backWidget;
  final bool flipped;
  final RotateSide rotateSide;
  final Duration animationDuration;

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final _animationController = AnimationController(
    duration: widget.animationDuration,
    vsync: this,
    value: widget.flipped ? 1 : 0,
  );

  @override
  void didUpdateWidget(FlipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _animationController.duration = widget.animationDuration;
    if (widget.flipped != oldWidget.flipped) {
      widget.flipped
          ? _animationController.forward()
          : _animationController.reverse();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final angle = _animationController.value * math.pi;
        final isFrontVisible = angle <= math.pi / 2;
        final rotateX =
            widget.rotateSide == RotateSide.top ||
            widget.rotateSide == RotateSide.bottom;
        final direction =
            widget.rotateSide == RotateSide.left ||
                widget.rotateSide == RotateSide.top
            ? 1
            : -1;
        final transform = Matrix4.identity()..setEntry(3, 2, 0.001);
        if (rotateX) {
          transform.rotateX(angle * direction);
        } else {
          transform.rotateY(angle * direction);
        }

        return Transform(
          alignment: Alignment.center,
          transform: transform,
          child: isFrontVisible
              ? widget.frontWidget
              : Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..rotateX(rotateX ? math.pi : 0)
                    ..rotateY(rotateX ? 0 : math.pi),
                  child: widget.backWidget,
                ),
        );
      },
    );
  }
}
