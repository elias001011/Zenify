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
import 'package:musify/main.dart';
import 'package:musify/screens/now_playing_page.dart';
import 'package:musify/widgets/desktop_volume_control.dart';
import 'package:musify/widgets/marquee.dart';
import 'package:musify/widgets/now_playing/now_playing_controls.dart';
import 'package:musify/widgets/now_playing/player_actions.dart';
import 'package:musify/widgets/now_playing/player_chrome.dart';
import 'package:musify/widgets/playback_icon_button.dart';
import 'package:musify/widgets/skip_icon_button.dart';
import 'package:musify/widgets/song_artwork.dart';
import 'package:rxdart/rxdart.dart';

/// Whether a song follows the current one. The mini player's body rebuilds
/// only when this changes: the play button follows playback on its own.
bool _hasNext(PlaybackState playback, List<MediaItem> queue) =>
    queue.length > 1 &&
    ((playback.queueIndex ?? 0) < queue.length - 1 ||
        playback.repeatMode == AudioServiceRepeatMode.all);

/// The stream doesn't replay, so a mini player built later (the layout
/// switching between dock and rail) starts from this.
bool _currentHasNext() =>
    _hasNext(audioHandler.playbackState.value, audioHandler.queue.value);

class MiniPlayer extends StatefulWidget {
  /// Drawn straight on the dock's floating surface.
  const MiniPlayer({super.key, this.wide = false});

  final bool wide;

  static const double playerHeight = 72;
  static const double _borderRadius = 20;
  static const double _artworkSize = 52;
  static const double _artworkRadius = 14;

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  late final _hasNextStream = Rx.combineLatest2(
    audioHandler.playbackState,
    audioHandler.queue,
    _hasNext,
  ).distinct();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PlayerChrome(
      style: PlayerChromeStyle.dock,
      child: LayoutBuilder(
        builder: (context, constraints) => AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: StreamBuilder<MediaItem?>(
            initialData: audioHandler.mediaItem.value,
            stream: audioHandler.mediaItem,
            builder: (context, mediaSnapshot) {
              final metadata = mediaSnapshot.data;
              if (metadata == null) return const SizedBox.shrink();

              return StreamBuilder<bool>(
                initialData: _currentHasNext(),
                stream: _hasNextStream,
                builder: (context, nextSnapshot) => _MiniPlayerBody(
                  wide: widget.wide && constraints.maxWidth >= 900,
                  colorScheme: colorScheme,
                  metadata: metadata,
                  hasNext: nextSnapshot.data ?? false,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MiniPlayerBody extends StatefulWidget {
  const _MiniPlayerBody({
    required this.colorScheme,
    required this.metadata,
    required this.wide,
    required this.hasNext,
  });

  final ColorScheme colorScheme;
  final MediaItem metadata;
  final bool wide;
  final bool hasNext;

  @override
  State<_MiniPlayerBody> createState() => _MiniPlayerBodyState();
}

class _MiniPlayerBodyState extends State<_MiniPlayerBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1, end: 0.98).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  static const double _dragThresholdForNavigation = 10;

  void _handleVerticalDrag(DragUpdateDetails details) {
    if ((details.primaryDelta ?? 0) < -_dragThresholdForNavigation) {
      _navigateToNowPlaying();
    }
  }

  void _navigateToNowPlaying() {
    Navigator.of(context).push(buildNowPlayingRoute());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final metadata = widget.metadata;

    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _animationController.forward(),
            onTapUp: (_) => _animationController.reverse(),
            onTapCancel: () => _animationController.reverse(),
            onVerticalDragUpdate: _handleVerticalDrag,
            onTap: _navigateToNowPlaying,
            child: SizedBox(
              height: MiniPlayer.playerHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(MiniPlayer._borderRadius),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: widget.wide
                      ? _wideBody(context)
                      : Row(
                          children: [
                            _ArtworkWidget(metadata: metadata),
                            Expanded(child: _metadata(context)),
                            _ControlsWidget(
                              colorScheme: colorScheme,
                              hasNext: widget.hasNext,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _metadata(BuildContext context) => AnimatedSwitcher(
    duration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 300),
    switchInCurve: Curves.easeIn,
    switchOutCurve: Curves.easeOut,
    layoutBuilder: (currentChild, previousChildren) => Stack(
      alignment: AlignmentDirectional.centerStart,
      children: [...previousChildren, if (currentChild != null) currentChild],
    ),
    transitionBuilder: (child, animation) =>
        FadeTransition(opacity: animation, child: child),
    child: KeyedSubtree(
      key: ValueKey(widget.metadata.id),
      child: _MetadataWidget(
        title: widget.metadata.title,
        artist: widget.metadata.artist,
        colorScheme: widget.colorScheme,
      ),
    ),
  );

  Widget _wideBody(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final colors = widget.colorScheme;
      final live = widget.metadata.extras?['isLive'] == true;
      return Row(
        children: [
          Expanded(
            child: Row(
              children: [
                _ArtworkWidget(metadata: widget.metadata),
                Expanded(child: _metadata(context)),
              ],
            ),
          ),
          SizedBox(
            width: 164,
            child: live
                ? PlaybackIconButton(
                    iconSize: 22,
                    iconColor: colors.onPrimary,
                    backgroundColor: colors.primary,
                  )
                : PlaybackTransportControls(
                    colorScheme: colors,
                    buttonConstraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    buttonPadding: const EdgeInsets.all(6),
                    controlIconSize: 22,
                    buttonSpacing: 8,
                    minButtonSize: 44,
                    playPadding: const EdgeInsets.all(10),
                  ),
          ),
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: PlayerActions(metadata: widget.metadata, miniPlayer: true),
            ),
          ),
        ],
      );
    },
  );
}

class _ArtworkWidget extends StatelessWidget {
  const _ArtworkWidget({required this.metadata});
  final MediaItem metadata;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Hero(
        tag: 'now_playing_artwork',
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MiniPlayer._artworkRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SongArtworkWidget(
            metadata: metadata,
            size: MiniPlayer._artworkSize,
            errorWidgetIconSize: 24,
            borderRadius: MiniPlayer._artworkRadius,
          ),
        ),
      ),
    );
  }
}

class _MetadataWidget extends StatelessWidget {
  const _MetadataWidget({
    required this.title,
    required this.artist,
    required this.colorScheme,
  });

  final String title;
  final String? artist;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarqueeWidget(
            manualScrollEnabled: false,
            animationDuration: const Duration(seconds: 8),
            backDuration: const Duration(seconds: 2),
            pauseDuration: const Duration(seconds: 2),
            child: Text(
              title,
              style: TextStyle(
                color: colorScheme.secondary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (artist != null && artist!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              artist!,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

class _ControlsWidget extends StatelessWidget {
  const _ControlsWidget({required this.colorScheme, required this.hasNext});

  final ColorScheme colorScheme;
  final bool hasNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (supportsDesktopVolumeControl) ...[
          const DesktopVolumeButton(),
          const SizedBox(width: 4),
        ],
        // The same filled circle as the wide mini player, on every platform.
        PlaybackIconButton(
          iconSize: 22,
          iconColor: colorScheme.onPrimary,
          backgroundColor: colorScheme.primary,
          filled: true,
          buttonSize: 44,
        ),
        if (hasNext) ...[
          const SizedBox(width: 4),
          SkipIconButton(
            forward: true,
            onPressed: audioHandler.skipToNext,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            icon: FluentIcons.next_24_filled,
            color: colorScheme.onSurfaceVariant,
            iconSize: 24,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ],
    );
  }
}
