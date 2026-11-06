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

import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/services/local_files_service.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/widgets/now_playing/marquee_text_widget.dart';
import 'package:musify/widgets/now_playing/player_chrome.dart';
import 'package:musify/widgets/playback_icon_button.dart';
import 'package:musify/widgets/position_slider.dart';
import 'package:musify/widgets/skip_icon_button.dart';

class NowPlayingControls extends StatelessWidget {
  const NowPlayingControls({
    super.key,
    required this.size,
    required this.adjustedIconSize,
    required this.adjustedMiniIconSize,
    required this.metadata,
  });

  final Size size;
  final double adjustedIconSize;
  final double adjustedMiniIconSize;
  final MediaItem metadata;

  @override
  Widget build(BuildContext context) {
    final isDesktop = size.width > 800;

    final titleFontSize = getResponsiveTitleFontSize(size);
    final artistFontSize = getResponsiveArtistFontSize(size);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final isCompact = availableHeight < 280;
        final isVeryCompact = availableHeight < 200;

        final spacing = isVeryCompact
            ? 2.0
            : isCompact
            ? 4.0
            : 8.0;
        final iconScale = isVeryCompact
            ? 0.65
            : isCompact
            ? 0.75
            : 1.0;
        final fontScale = isCompact ? 0.9 : 1.0;

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isCompact) const Spacer(),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 16 : 24,
                vertical: spacing,
              ),
              child: NowPlayingTitle(
                metadata: metadata,
                titleSize: titleFontSize * fontScale,
                artistSize: artistFontSize * fontScale,
                spacing: spacing,
              ),
            ),
            if (!isCompact) const Spacer(),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isDesktop ? 400 : constraints.maxWidth,
              ),
              child: PlayerTransport(
                iconSize: adjustedIconSize * iconScale,
                miniIconSize: adjustedMiniIconSize * iconScale,
                gap: spacing,
              ),
            ),
            if (!isCompact) const Spacer(),
          ],
        );
      },
    );
  }
}

/// The song title and artist, scrolling when long. Tapping the artist opens
/// their page; a long press copies both.
class NowPlayingTitle extends StatelessWidget {
  const NowPlayingTitle({
    super.key,
    required this.metadata,
    required this.titleSize,
    required this.artistSize,
    this.spacing = 8,
    this.alignment = CrossAxisAlignment.center,
  });

  final MediaItem metadata;
  final double titleSize;
  final double artistSize;
  final double spacing;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canOpenArtist = _canOpenArtist(metadata);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () => _copyNowPlayingSong(context, metadata),
          child: MarqueeTextWidget(
            text: metadata.title,
            fontColor: colorScheme.onSurface,
            fontSize: titleSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: spacing),
        if (metadata.artist != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canOpenArtist
                ? () => _openArtistPage(context, metadata)
                : null,
            onLongPress: () => _copyNowPlayingSong(context, metadata),
            child: MarqueeTextWidget(
              text: metadata.artist!,
              fontColor: colorScheme.onSurfaceVariant,
              fontSize: artistSize,
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
    );
  }

  bool _canOpenArtist(MediaItem metadata) {
    final info = _extractArtistInfo(metadata);
    // A local file has no artist page, and its id is never sent to YouTube.
    if (isLocalSongId(info.sourceSongId)) return false;
    return !offlineMode.value &&
        (info.artist.isNotEmpty ||
            info.artistId.isNotEmpty ||
            info.sourceSongId.isNotEmpty);
  }

  void _openArtistPage(BuildContext context, MediaItem metadata) {
    final info = _extractArtistInfo(metadata);
    final destination = NavigationManager.artistDestination(
      context,
      name: info.artist,
      artistId: info.artistId,
      sourceSongId: info.sourceSongId,
      videoAuthor: info.videoAuthor,
    );
    if (destination == null) return;

    final router = GoRouter.of(context);
    Navigator.of(context).pop();
    unawaited(router.push(destination.path, extra: destination.extra));
  }

  ({String artist, String artistId, String sourceSongId, String videoAuthor})
  _extractArtistInfo(MediaItem metadata) {
    return (
      artist: metadata.artist?.trim() ?? '',
      artistId: metadata.extras?['artistId']?.toString().trim() ?? '',
      sourceSongId: metadata.extras?['ytid']?.toString().trim() ?? '',
      videoAuthor: metadata.extras?['videoAuthor']?.toString().trim() ?? '',
    );
  }
}

Future<void> _copyNowPlayingSong(
  BuildContext context,
  MediaItem metadata,
) async {
  final artist = metadata.artist?.trim();
  final title = metadata.title.trim();
  final text = artist == null || artist.isEmpty ? title : '$artist - $title';
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showToast(context, context.l10n!.songInfoCopied);
}

/// How big the playback buttons are, in dp: the play icon and the box that
/// takes its touch, the icons of previous and next, and those of shuffle and
/// repeat.
typedef PlayerButtonSizes = ({
  double play,
  double box,
  double skip,
  double mode,
});

/// The phone's buttons for the width they have: the play icon takes 15% of
/// it, from 44 to 56, and the other buttons follow its size.
PlayerButtonSizes phoneButtonSizes(double width) {
  final play = (width * 0.15).clamp(44.0, 56.0);
  return (
    play: play,
    box: play + 12,
    skip: play * 0.7,
    mode: (width * 0.068).clamp(20.0, 24.0),
  );
}

/// The same proportions in the mini player's 40 dp box.
const dockButtonSizes = (play: 30.0, box: 40.0, skip: 21.6, mode: 18.0);

/// The progress bar, the times and the playback buttons. One column, so the
/// progress bar, the times and the icons of shuffle and repeat all begin and
/// end at the same edges, the artwork's, whatever the layout around it.
class PlayerTransport extends StatelessWidget {
  /// Either the [sizes] of the buttons, taken as given, or the [iconSize] of
  /// the play button and the [miniIconSize] of shuffle and repeat, which are
  /// scaled down as the room gets narrower. With [controlsOnly], just previous,
  /// play and next, centred: a radio station has no progress bar, shuffle or
  /// repeat.
  const PlayerTransport({
    super.key,
    this.sizes,
    this.iconSize,
    this.miniIconSize,
    this.gap = 6,
    this.controlsOnly = false,
  }) : assert(
         (sizes != null) != (iconSize != null && miniIconSize != null),
         'Give the sizes of the buttons, or the icon sizes to scale.',
       );
  final PlayerButtonSizes? sizes;
  final double? iconSize;
  final double? miniIconSize;

  /// Between the times and the buttons.
  final double gap;

  /// Only previous, play and next.
  final bool controlsOnly;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final scale = screenWidth < 360 ? 0.85 : 1.0;
    final responsiveIconSize = (iconSize ?? 0) * scale;
    final responsiveMiniIconSize = (miniIconSize ?? 0) * scale;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final isTight = maxWidth < 360;
        final isUltraTight = maxWidth < 320;

        final buttonSpacing = isUltraTight
            ? 6.0
            : isTight
            ? 10.0
            : 16.0;
        final minButtonSize = isTight ? 44.0 : 46.0;
        final buttonPadding = EdgeInsets.all(
          isUltraTight
              ? 6.0
              : isTight
              ? 8.0
              : 10.0,
        );

        final buttonConstraints = BoxConstraints(
          minWidth: minButtonSize,
          minHeight: minButtonSize,
        );

        final controlIconSize =
            sizes?.play ??
            responsiveIconSize *
                (isUltraTight
                    ? 0.75
                    : isTight
                    ? 0.85
                    : 0.92);
        final miniControlSize =
            sizes?.mode ??
            responsiveMiniIconSize *
                (isUltraTight
                    ? 0.8
                    : isTight
                    ? 0.9
                    : 1.0);
        // The room around the icon of shuffle and repeat inside their buttons:
        // the buttons are moved out by it, so the icons, not their touch
        // areas, are what lines up with the progress bar and the times.
        final iconInset =
            (math.max(
                  minButtonSize,
                  miniControlSize + buttonPadding.horizontal,
                ) -
                miniControlSize) /
            2;

        final controls = PlaybackTransportControls(
          colorScheme: colorScheme,
          buttonConstraints: buttonConstraints,
          buttonPadding: buttonPadding,
          controlIconSize: controlIconSize,
          buttonSpacing: buttonSpacing,
          minButtonSize: minButtonSize,
          skipIconSize: sizes?.skip,
          playButtonSize: sizes?.box,
        );
        if (controlsOnly) return Center(child: controls);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PositionSlider(),
            SizedBox(height: gap),
            Directionality(
              // Transport controls are not mirrored: their order, arrows and
              // the offsets above stay as they are in a right-to-left language.
              textDirection: TextDirection.ltr,
              child: Row(
                children: <Widget>[
                  Transform.translate(
                    offset: Offset(-iconInset, 0),
                    child: PlaybackModeButton(
                      repeat: false,
                      size: miniControlSize,
                      constraints: buttonConstraints,
                      padding: buttonPadding,
                    ),
                  ),
                  SizedBox(width: buttonSpacing),
                  Expanded(child: Center(child: controls)),
                  SizedBox(width: buttonSpacing),
                  Transform.translate(
                    offset: Offset(iconInset, 0),
                    child: PlaybackModeButton(
                      repeat: true,
                      size: miniControlSize,
                      constraints: buttonConstraints,
                      padding: buttonPadding,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Shared by the full player and desktop dock, backed by the same audio state.
class PlaybackModeButton extends StatelessWidget {
  const PlaybackModeButton({
    super.key,
    required this.repeat,
    this.size = 20,
    this.constraints = const BoxConstraints(minWidth: 44, minHeight: 44),
    this.padding = const EdgeInsets.all(8),
  });
  final bool repeat;
  final double size;
  final BoxConstraints constraints;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget button(bool active, IconData icon, VoidCallback pressed) =>
        IconButton(
          icon: Icon(icon),
          tooltip: repeat ? context.l10n!.repeat : context.l10n!.shuffle,
          iconSize: size,
          constraints: constraints,
          padding: padding,
          style: IconButton.styleFrom(
            foregroundColor: active ? colors.primary : colors.onSurfaceVariant,
            backgroundColor: Colors.transparent,
            side: BorderSide.none,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: pressed,
        );
    if (!repeat) {
      return ValueListenableBuilder<bool>(
        valueListenable: shuffleNotifier,
        builder: (_, active, _) => button(
          active,
          active
              ? FluentIcons.arrow_shuffle_24_filled
              : FluentIcons.arrow_shuffle_24_regular,
          () => audioHandler.setShuffleMode(
            active ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all,
          ),
        ),
      );
    }
    return ValueListenableBuilder<AudioServiceRepeatMode>(
      valueListenable: repeatNotifier,
      builder: (_, mode, _) => button(
        mode != AudioServiceRepeatMode.none,
        mode == AudioServiceRepeatMode.one
            ? FluentIcons.arrow_repeat_1_24_filled
            : mode == AudioServiceRepeatMode.all
            ? FluentIcons.arrow_repeat_all_24_filled
            : FluentIcons.arrow_repeat_all_24_regular,
        () => audioHandler.setRepeatMode(switch (mode) {
          AudioServiceRepeatMode.none =>
            audioHandler.queue.value.length <= 1
                ? AudioServiceRepeatMode.one
                : AudioServiceRepeatMode.all,
          AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
          _ => AudioServiceRepeatMode.none,
        }),
      ),
    );
  }
}

class PlaybackTransportControls extends StatelessWidget {
  const PlaybackTransportControls({
    super.key,
    required this.colorScheme,
    required this.buttonConstraints,
    required this.buttonPadding,
    required this.controlIconSize,
    required this.buttonSpacing,
    required this.minButtonSize,
    this.skipIconSize,
    this.playButtonSize,
  });

  final ColorScheme colorScheme;
  final BoxConstraints buttonConstraints;
  final EdgeInsets buttonPadding;
  final double controlIconSize;
  final double buttonSpacing;
  final double minButtonSize;

  /// The icons of previous and next; by default a share of [controlIconSize].
  final double? skipIconSize;

  /// The box of the play button; by default 44 in the dock and 52 elsewhere.
  final double? playButtonSize;

  @override
  Widget build(BuildContext context) {
    // Previous, play and next keep their order and direction in every language.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: StreamBuilder<List<MediaItem>>(
        stream: audioHandler.queue,
        builder: (context, snapshot) {
          // A station is a radio: previous and next switch station, and repeat
          // has no meaning for it. Switching pushes a new queue, so this
          // rebuilds with it.
          final live =
              audioHandler.mediaItem.valueOrNull?.extras?['isLive'] == true;
          return ValueListenableBuilder<AudioServiceRepeatMode>(
            valueListenable: repeatNotifier,
            builder: (_, repeatMode, __) {
              final repeats =
                  !live && repeatMode != AudioServiceRepeatMode.none;
              return FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PlaybackControlButton(
                      icon: FluentIcons.previous_24_filled,
                      forward: false,
                      isEnabled: audioHandler.hasPrevious || repeats,
                      tooltip: context.l10n!.skipToPrevious,
                      onPressed: () => audioHandler.skipToPrevious(),
                      colorScheme: colorScheme,
                      buttonConstraints: buttonConstraints,
                      buttonPadding: buttonPadding,
                      controlIconSize: controlIconSize,
                      skipIconSize: skipIconSize,
                      minButtonSize: minButtonSize,
                    ),
                    SizedBox(width: buttonSpacing),
                    PlaybackIconButton(
                      iconColor: colorScheme.onSurface,
                      backgroundColor: Colors.transparent,
                      buttonSize:
                          playButtonSize ??
                          (PlayerChrome.of(context) == PlayerChromeStyle.dock
                              ? 44
                              : 52),
                      iconSize: controlIconSize,
                    ),
                    SizedBox(width: buttonSpacing),
                    _PlaybackControlButton(
                      icon: FluentIcons.next_24_filled,
                      forward: true,
                      isEnabled: audioHandler.hasNext || repeats,
                      tooltip: context.l10n!.skipToNext,
                      onPressed: () =>
                          !live && repeatMode == AudioServiceRepeatMode.one
                          ? audioHandler.playAgain()
                          : audioHandler.skipToNext(),
                      colorScheme: colorScheme,
                      buttonConstraints: buttonConstraints,
                      buttonPadding: buttonPadding,
                      controlIconSize: controlIconSize,
                      skipIconSize: skipIconSize,
                      minButtonSize: minButtonSize,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _PlaybackControlButton extends StatelessWidget {
  const _PlaybackControlButton({
    required this.icon,
    required this.forward,
    required this.isEnabled,
    required this.tooltip,
    required this.onPressed,
    required this.colorScheme,
    required this.buttonConstraints,
    required this.buttonPadding,
    required this.controlIconSize,
    required this.skipIconSize,
    required this.minButtonSize,
  });

  final IconData icon;
  final bool forward;
  final bool isEnabled;
  final String tooltip;
  final Future<void> Function() onPressed;
  final ColorScheme colorScheme;
  final BoxConstraints buttonConstraints;
  final EdgeInsets buttonPadding;
  final double controlIconSize;
  final double? skipIconSize;
  final double minButtonSize;

  @override
  Widget build(BuildContext context) {
    return SkipIconButton(
      forward: forward,
      icon: icon,
      color: isEnabled
          ? colorScheme.onSurface
          : colorScheme.onSurface.withValues(alpha: 0.3),
      tooltip: tooltip,
      constraints: buttonConstraints,
      iconSize: skipIconSize ?? controlIconSize * 0.75,
      onPressed: isEnabled ? onPressed : null,
      style: IconButton.styleFrom(
        backgroundColor: Colors.transparent,
        disabledBackgroundColor: Colors.transparent,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: buttonPadding,
        minimumSize: Size(minButtonSize, minButtonSize),
      ),
    );
  }
}
