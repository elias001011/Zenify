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
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/utilities/platform_utils.dart';
import 'package:musify/widgets/click_detector.dart';
import 'package:musify/widgets/now_playing/player_actions.dart';

bool get supportsDesktopVolumeControl => isDesktopPlatform;

IconData volumeIcon(double volume) {
  if (volume <= 0.0) return FluentIcons.speaker_mute_24_regular;
  if (volume < 0.5) return FluentIcons.speaker_1_24_regular;
  return FluentIcons.speaker_2_24_regular;
}

/// The volume bar: a thin upright pill, filled from the bottom up to the
/// volume, with the speaker at its foot. Dragging or tapping the bar sets the
/// volume, the speaker mutes and the mouse wheel scrolls it.
class DesktopVolumeControl extends StatelessWidget {
  const DesktopVolumeControl({super.key, this.length = defaultLength});

  static const double thickness = 36;
  static const double defaultLength = 152;
  static const double _iconSize = 20;

  final double length;

  @override
  Widget build(BuildContext context) {
    if (!supportsDesktopVolumeControl) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return StreamBuilder<double>(
      stream: audioHandler.volumeStream,
      initialData: audioHandler.volume,
      builder: (context, snapshot) {
        final volume = (snapshot.data ?? 1.0).clamp(0.0, 1.0);
        // The speaker is drawn twice: in the track's colour, and in the
        // fill's inverse where the fill reaches it.
        Widget speaker(Color color) => Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: (thickness - _iconSize) / 2),
            child: Icon(volumeIcon(volume), size: _iconSize, color: color),
          ),
        );
        return SizedBox(
          width: thickness,
          height: length,
          child: Listener(
            onPointerSignal: _scrolled,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(thickness / 2),
              child: Stack(
                children: [
                  // A slider lies down; turned up it grows from the bottom,
                  // whatever the reading direction.
                  Positioned.fill(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: thickness,
                            trackShape: const RectangularSliderTrackShape(),
                            activeTrackColor: colors.onSurface,
                            inactiveTrackColor: colors.surfaceContainerHighest,
                            thumbShape: SliderComponentShape.noThumb,
                            overlayShape: SliderComponentShape.noOverlay,
                            padding: EdgeInsets.zero,
                          ),
                          child: Slider(
                            value: volume,
                            semanticFormatterCallback: (value) =>
                                '${(value * 100).round()}%',
                            onChanged: audioHandler.setVolume,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Stack(
                        children: [
                          speaker(colors.onSurfaceVariant),
                          ClipRect(
                            clipper: _FillClipper(volume),
                            child: speaker(colors.surfaceContainerHighest),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: thickness,
                    child: Tooltip(
                      message: context.l10n!.volume,
                      child: ClickDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: audioHandler.toggleMute,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _scrolled(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta.dy != 0
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (delta == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      audioHandler.setVolume(
        (audioHandler.volume - delta / 400).clamp(0.0, 1.0),
      );
    });
  }
}

/// The part of the bar that the fill covers, from the bottom.
class _FillClipper extends CustomClipper<Rect> {
  const _FillClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    0,
    size.height - size.height * fraction,
    size.width,
    size.height,
  );

  @override
  bool shouldReclip(_FillClipper old) => old.fraction != fraction;
}

/// The volume button of the player and the desktop mini player, opening
/// [DesktopVolumeControl] above it. Only desktop has it.
class DesktopVolumeButton extends StatelessWidget {
  const DesktopVolumeButton({super.key});

  @override
  Widget build(BuildContext context) {
    if (!supportsDesktopVolumeControl) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return MenuAnchor(
      alignmentOffset: const Offset(
        -DesktopVolumeControl.thickness / 2,
        -(DesktopVolumeControl.defaultLength + 10),
      ),
      style: MenuStyle(
        alignment: Alignment.topCenter,
        elevation: const WidgetStatePropertyAll(4),
        shadowColor: WidgetStatePropertyAll(
          Colors.black.withValues(alpha: 0.22),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHighest),
        shape: WidgetStatePropertyAll(
          StadiumBorder(
            side: BorderSide(
              color: colors.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
      ),
      menuChildren: const [DesktopVolumeControl()],
      builder: (context, controller, child) => StreamBuilder<double>(
        stream: audioHandler.volumeStream,
        initialData: audioHandler.volume,
        builder: (context, snapshot) => PlayerActionButton(
          icon: volumeIcon(snapshot.data ?? audioHandler.volume),
          tooltip: context.l10n!.volume,
          active: controller.isOpen,
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
        ),
      ),
    );
  }
}
