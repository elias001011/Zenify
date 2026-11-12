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

import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/motion.dart';
import 'package:musify/widgets/now_playing/now_playing_artwork.dart';

/// A skip button. Tapped, its icon leans a few pixels towards the skip and
/// back, and the cover slides the same way.
class SkipIconButton extends StatefulWidget {
  const SkipIconButton({
    super.key,
    required this.forward,
    required this.icon,
    required this.onPressed,
    this.color,
    this.iconSize,
    this.tooltip,
    this.constraints,
    this.style,
    this.visualDensity,
    this.splashColor,
    this.highlightColor,
  });

  /// Next is forward, previous is back.
  final bool forward;
  final IconData icon;
  final Future<void> Function()? onPressed;
  final Color? color;
  final double? iconSize;
  final String? tooltip;
  final BoxConstraints? constraints;
  final ButtonStyle? style;
  final VisualDensity? visualDensity;
  final Color? splashColor;
  final Color? highlightColor;

  @override
  State<SkipIconButton> createState() => _SkipIconButtonState();
}

class _SkipIconButtonState extends State<SkipIconButton>
    with SingleTickerProviderStateMixin {
  late final _nudge = AnimationController(vsync: this, duration: Motion.medium);

  @override
  void dispose() {
    _nudge.dispose();
    super.dispose();
  }

  Future<void> _onPressed() async {
    final onPressed = widget.onPressed;
    if (onPressed == null) return;
    _nudge.forward(from: 0);
    await skipWithDirection(widget.forward ? 1 : -1, onPressed);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: AnimatedBuilder(
        animation: _nudge,
        builder: (context, child) => Transform.translate(
          // A half sine: out and back, with no jolt at either end.
          offset: Offset((widget.forward ? 4 : -4) * sin(pi * _nudge.value), 0),
          child: child,
        ),
        child: Icon(widget.icon, color: widget.color),
      ),
      tooltip: widget.tooltip,
      iconSize: widget.iconSize,
      constraints: widget.constraints,
      style: widget.style,
      visualDensity: widget.visualDensity,
      splashColor: widget.splashColor,
      highlightColor: widget.highlightColor,
      onPressed: widget.onPressed == null ? null : _onPressed,
    );
  }
}
