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

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';

Widget buildPlaybackIconButton(
  double iconSize,
  Color iconColor,
  Color backgroundColor, {
  EdgeInsets? padding,
  bool filled = false,
  double? buttonSize,
}) {
  return StreamBuilder<PlaybackState>(
    initialData: audioHandler.playbackState.value,
    stream: audioHandler.playbackState.distinct((previous, current) {
      // Only rebuild if relevant state changes
      return previous.playing == current.playing &&
          previous.processingState == current.processingState;
    }),
    builder: (context, snapshot) {
      final playbackState = snapshot.data;
      final processingState = playbackState?.processingState;
      final isPlaying = playbackState?.playing ?? false;

      Widget iconWidget;
      VoidCallback? onPressed;
      String? semanticLabel;

      if (processingState == AudioProcessingState.loading ||
          processingState == AudioProcessingState.buffering) {
        iconWidget = SizedBox(
          width: iconSize,
          height: iconSize,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            valueColor: AlwaysStoppedAnimation<Color>(iconColor),
          ),
        );
        onPressed = null;
        semanticLabel = context.l10n!.loading;
      } else if (processingState == AudioProcessingState.completed) {
        iconWidget = Icon(
          FluentIcons.arrow_counterclockwise_24_regular,
          color: iconColor,
          size: iconSize,
        );
        onPressed = () => audioHandler.playAgain();
        semanticLabel = context.l10n!.replay;
      } else {
        iconWidget = Icon(
          isPlaying
              ? (filled
                    ? FluentIcons.pause_24_filled
                    : FluentIcons.pause_24_regular)
              : (filled
                    ? FluentIcons.play_24_filled
                    : FluentIcons.play_24_regular),
          color: iconColor,
          size: iconSize,
        );
        onPressed = isPlaying ? audioHandler.pause : audioHandler.play;
        semanticLabel = isPlaying ? context.l10n!.pause : context.l10n!.play;
      }

      // Desktop's plain transport uses the same centred IconButton layout
      // as its neighbours, with an explicit box and no oversized inner padding.
      if (filled && buttonSize != null) {
        return SizedBox.square(
          dimension: buttonSize,
          child: IconButton(
            tooltip: semanticLabel,
            onPressed: onPressed,
            iconSize: iconSize,
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              minimumSize: Size.square(buttonSize),
              fixedSize: Size.square(buttonSize),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: backgroundColor,
              side: BorderSide.none,
              shape: const CircleBorder(),
            ),
            icon: PlaybackIconSwitcher(
              stateKey: (processingState, isPlaying),
              child: iconWidget,
            ),
          ),
        );
      }

      return RawMaterialButton(
        elevation: 0,
        onPressed: onPressed,
        fillColor: backgroundColor,
        splashColor: Colors.transparent,
        padding: padding ?? EdgeInsets.all(iconSize * 0.35),
        shape: const CircleBorder(),
        constraints: BoxConstraints.tightFor(
          width: buttonSize ?? iconSize * 2,
          height: buttonSize ?? iconSize * 2,
        ),
        materialTapTargetSize: MaterialTapTargetSize.padded,
        child: Semantics(
          label: semanticLabel,
          button: true,
          child: PlaybackIconSwitcher(
            stateKey: (processingState, isPlaying),
            child: iconWidget,
          ),
        ),
      );
    },
  );
}

/// Cross-fades a play, pause or replay icon as the state it shows changes.
/// `stateKey` names that state; the icon swaps when it changes.
class PlaybackIconSwitcher extends StatelessWidget {
  const PlaybackIconSwitcher({
    super.key,
    required this.stateKey,
    required this.child,
  });

  final Object stateKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
  }
}

class PlaybackIconButton extends StatelessWidget {
  const PlaybackIconButton({
    super.key,
    required this.iconSize,
    required this.iconColor,
    required this.backgroundColor,
    this.padding,
    this.filled = false,
    this.buttonSize,
  });

  final double iconSize;
  final Color iconColor;
  final Color backgroundColor;
  final EdgeInsets? padding;
  final bool filled;
  final double? buttonSize;

  @override
  Widget build(BuildContext context) {
    return buildPlaybackIconButton(
      iconSize,
      iconColor,
      backgroundColor,
      padding: padding,
      filled: filled,
      buttonSize: buttonSize,
    );
  }
}
