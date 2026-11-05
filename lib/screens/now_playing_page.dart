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

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/mediaitem.dart';
import 'package:musify/widgets/app_notice.dart';
import 'package:musify/widgets/artwork_glow.dart';
import 'package:musify/widgets/desktop_volume_control.dart';
import 'package:musify/widgets/now_playing/lyrics_panel.dart';
import 'package:musify/widgets/now_playing/now_playing_artwork.dart';
import 'package:musify/widgets/now_playing/now_playing_controls.dart';
import 'package:musify/widgets/now_playing/player_actions.dart';
import 'package:musify/widgets/now_playing/player_chrome.dart';
import 'package:musify/widgets/queue_list_view.dart';

class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

/// Lets the player shortcut tell whether the player is the top route.
const String nowPlayingRouteName = 'nowPlaying';

Route<void> buildNowPlayingRoute() {
  return PageRouteBuilder<void>(
    settings: const RouteSettings(name: nowPlayingRouteName),
    pageBuilder: (context, animation, _) => const NowPlayingPage(),
    reverseTransitionDuration: const Duration(milliseconds: 250),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final tween = Tween(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeInOut));
      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  /// Open in the artwork area on phones, or beside it on wide screens.
  PlayerPanel? _panel;

  /// Shared by this screen's blurred surfaces, kept across rebuilds.
  final _backdropKey = BackdropKey();
  Animation<double>? _routeAnimation;
  bool _backgroundVisible = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (_routeAnimation == animation) return;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = animation;
    animation?.addStatusListener(_onRouteStatus);
    // While the route is being built its animation still reads "completed"
    // (a proxy without its controller), which would let the glow expand as
    // the player rises. Trust it only after the first frame.
    _backgroundVisible = animation == null;
    if (animation != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && animation.status == AnimationStatus.completed) {
          _onRouteStatus(AnimationStatus.completed);
        }
      });
    }
  }

  void _onRouteStatus(AnimationStatus status) {
    final visible = status == AnimationStatus.completed;
    if (mounted && visible != _backgroundVisible) {
      setState(() => _backgroundVisible = visible);
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    super.dispose();
  }

  void _onPanel(PlayerPanel panel) =>
      setState(() => _panel = _panel == panel ? null : panel);

  @override
  Widget build(BuildContext context) {
    final layout = _PlayerLayout.of(MediaQuery.sizeOf(context));
    return PlayerChrome(
      style: PlayerChromeStyle.plain,
      child: PopScope(
        canPop: layout == _PlayerLayout.wide || _panel == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _panel = null);
        },
        child: Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          body: StreamBuilder<MediaItem?>(
            initialData: audioHandler.mediaItem.value,
            stream: audioHandler.mediaItem,
            builder: (context, snapshot) {
              final metadata = snapshot.data;
              if (metadata == null) {
                return const Center(child: CircularProgressIndicator());
              }
              final panel = _panel;
              final actions = PlayerActions(
                metadata: metadata,
                panel: panel,
                onPanel: _onPanel,
                showVolume: layout != _PlayerLayout.wide,
              );
              // Its own group: during the slide its surfaces sit over the shell's.
              return BackdropGroup(
                backdropKey: _backdropKey,
                child: Stack(
                  children: [
                    // Expands once the player has slid up.
                    Positioned.fill(
                      child: PageGlow(
                        source: mediaItemArtworkSource(metadata),
                        waiting: !_backgroundVisible,
                        cacheKey: 'now-playing',
                      ),
                    ),
                    SafeArea(
                      child: layout == _PlayerLayout.wide
                          ? _WideLayout(
                              metadata: metadata,
                              actions: actions,
                              panel: panel,
                            )
                          : _CompactLayout(
                              metadata: metadata,
                              actions: actions,
                              panel: panel,
                              onClosePanel: () => setState(() => _panel = null),
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _PlayerLayout {
  /// Queue and lyrics open beside the artwork.
  wide,

  /// Upright phones: lyrics and queue take the artwork's place.
  upright,

  /// Phones on their side: queue or lyrics beside playback.
  sideways;

  static _PlayerLayout of(Size size) => size.width >= 900 && size.height >= 560
      ? wide
      : size.height >= size.width
      ? upright
      : sideways;
}

class _CloseButton extends StatelessWidget {
  const _CloseButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: IconButton(
          iconSize: 26,
          icon: const Icon(FluentIcons.chevron_down_24_regular),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }
}

/// Phones: the artwork, the song and playback, then the action bar. With
/// a panel open, the song moves to a small header and its content takes the
/// artwork's place.
class _CompactLayout extends StatelessWidget {
  const _CompactLayout({
    required this.metadata,
    required this.actions,
    required this.panel,
    required this.onClosePanel,
  });

  final MediaItem metadata;
  final Widget actions;
  final PlayerPanel? panel;
  final VoidCallback onClosePanel;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isLive = metadata.extras?['isLive'] ?? false;
    final iconSize = size.width < 360 ? 42.0 : (size.width < 400 ? 48.0 : 52.0);
    final miniIconSize = size.width < 360 ? 20.0 : 24.0;
    const margin = 20.0;

    final controls = isLive
        ? const SizedBox.shrink()
        : NowPlayingControls(
            size: size,
            adjustedIconSize: iconSize,
            adjustedMiniIconSize: miniIconSize,
            metadata: metadata,
          );
    Widget artwork(BoxConstraints constraints, double share) => Center(
      child: NowPlayingArtwork(
        metadata: metadata,
        size: min(constraints.maxWidth * share, constraints.maxHeight) - 8,
      ),
    );

    final stage = _PlayerLayout.of(size) == _PlayerLayout.sideways
        ? Row(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: switch (panel) {
                    PlayerPanel.queue => const QueueWidget(embedded: true),
                    PlayerPanel.lyrics => LyricsPanel(metadata: metadata),
                    null => LayoutBuilder(
                      builder: (context, c) => artwork(c, 1),
                    ),
                  },
                ),
              ),
              const SizedBox(width: 24),
              Expanded(child: controls),
            ],
          )
        : _UprightStage(
            metadata: metadata,
            panel: panel,
            onClosePanel: onClosePanel,
            buttonSizes: phoneButtonSizes(size.width - margin * 2),
          );

    return Column(
      children: [
        const _CloseButton(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: margin),
            child: stage,
          ),
        ),
        // The same plain row as the wide player, shrunk to fit a small phone.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: FittedBox(fit: BoxFit.scaleDown, child: actions),
        ),
      ],
    );
  }
}

/// The upright phone player. The song and playback sit together at the
/// bottom, where the thumb is; above them the artwork takes the whole width,
/// or, with a panel, the same artwork shrinks into a header beside the song
/// and the panel fills the rest, as Tidal does. One layout that moves, not a
/// second page over the first, and playback does not move with it.
class _UprightStage extends StatefulWidget {
  const _UprightStage({
    required this.metadata,
    required this.panel,
    required this.onClosePanel,
    required this.buttonSizes,
  });

  final MediaItem metadata;
  final PlayerPanel? panel;
  final VoidCallback onClosePanel;
  final PlayerButtonSizes buttonSizes;

  @override
  State<_UprightStage> createState() => _UprightStageState();
}

class _UprightStageState extends State<_UprightStage>
    with SingleTickerProviderStateMixin {
  static const _headerSize = 56.0;
  static const _titleHeight = 72.0;
  static const _gap = 24.0;

  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
    value: widget.panel != null ? 1 : 0,
  );
  late final _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );
  late final _panelFade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.4, 1, curve: Curves.easeIn),
  );

  /// Keep the closing panel built until it has faded out.
  late PlayerPanel? _builtPanel = widget.panel;

  @override
  void didUpdateWidget(_UprightStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.panel == oldWidget.panel) return;
    if (widget.panel != null) {
      _builtPanel = widget.panel;
      // Build the content before moving the artwork.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.panel != null) _controller.forward();
      });
    } else {
      _controller.reverse().whenCompleteOrCancel(() {
        if (mounted && widget.panel == null) setState(() => _builtPanel = null);
      });
    }
  }

  @override
  void dispose() {
    _panelFade.dispose();
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metadata = widget.metadata;
    final screen = MediaQuery.sizeOf(context);
    final isLive = metadata.extras?['isLive'] ?? false;

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final artSize = max(
                _headerSize,
                min(c.maxWidth, c.maxHeight - _titleHeight - _gap),
              );
              // What the artwork and the song leave of the height goes above
              // the artwork and between it and the song: the song stays at the
              // bottom, next to playback.
              final slack = max<double>(
                0,
                c.maxHeight - (artSize + _gap + _titleHeight),
              );
              final artOrigin = Offset((c.maxWidth - artSize) / 2, slack / 2);
              // Laid out once at full size and scaled, so the artwork keeps
              // its decoded image while it moves.
              final artwork = NowPlayingArtwork(
                metadata: metadata,
                size: artSize,
                slideOnSkip: widget.panel == null,
              );
              // Built once: the frames of the move only reposition and fade
              // them.
              final panel = _builtPanel == PlayerPanel.queue
                  ? const QueueWidget(embedded: true)
                  : LyricsPanel(metadata: metadata);
              // Lined up with the progress bar under it, as the artwork is.
              final songTitle = Align(
                alignment: AlignmentDirectional.bottomStart,
                child: NowPlayingTitle(
                  metadata: metadata,
                  titleSize: getResponsiveTitleFontSize(screen) + 2,
                  artistSize: getResponsiveArtistFontSize(screen) + 1,
                  spacing: 6,
                  alignment: CrossAxisAlignment.start,
                ),
              );
              final headerTitle = Align(
                alignment: AlignmentDirectional.centerStart,
                child: NowPlayingTitle(
                  metadata: metadata,
                  titleSize: 17,
                  artistSize: 14,
                  spacing: 2,
                  alignment: CrossAxisAlignment.start,
                ),
              );

              return AnimatedBuilder(
                animation: _progress,
                child: artwork,
                builder: (context, artwork) {
                  final t = _progress.value;
                  final shown = artSize + (_headerSize - artSize) * t;
                  final art = Rect.fromLTWH(
                    artOrigin.dx * (1 - t),
                    artOrigin.dy * (1 - t),
                    shown,
                    shown,
                  );
                  // The title under the artwork stays where it is and leaves;
                  // the header's arrives beside the artwork.
                  final under = 1 - const Interval(0, 0.5).transform(t);
                  final beside = const Interval(0.5, 1).transform(t);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Keyed, so the artwork keeps its state (image, waves)
                      // while the others come and go before it.
                      if (_builtPanel != null)
                        Positioned.fill(
                          key: const ValueKey('panel'),
                          top: _headerSize + 12,
                          child: FadeTransition(
                            opacity: _panelFade,
                            child: IgnorePointer(
                              ignoring: t < 1,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: KeyedSubtree(
                                  key: ValueKey(_builtPanel),
                                  child: panel,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (under > 0)
                        Positioned(
                          key: const ValueKey('title'),
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: _titleHeight,
                          child: Opacity(opacity: under, child: songTitle),
                        ),
                      if (beside > 0)
                        Positioned(
                          key: const ValueKey('header'),
                          left: art.right + 14,
                          right: 0,
                          top: art.center.dy - _headerSize / 2,
                          height: _headerSize,
                          child: Opacity(opacity: beside, child: headerTitle),
                        ),
                      Positioned(
                        key: const ValueKey('artwork'),
                        left: art.left,
                        top: art.top,
                        child: Transform.scale(
                          scale: shown / artSize,
                          alignment: Alignment.topLeft,
                          // Same tree in both states, so the artwork keeps
                          // its state; as the header it goes back.
                          child: GestureDetector(
                            onTap: t > 0 ? widget.onClosePanel : null,
                            child: AbsorbPointer(
                              absorbing: t > 0,
                              child: artwork,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        if (!isLive) ...[
          const SizedBox(height: 14),
          // Notices float above the progress bar, not over the buttons.
          NoticeAbove(child: PlayerTransport(sizes: widget.buttonSizes)),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Wide listening stage: cover and transport beside lyrics or queue
/// directly on the ambient canvas.
class _WideLayout extends StatefulWidget {
  const _WideLayout({
    required this.metadata,
    required this.actions,
    required this.panel,
  });
  final MediaItem metadata;
  final Widget actions;
  final PlayerPanel? panel;

  @override
  State<_WideLayout> createState() => _WideLayoutState();
}

class _WideLayoutState extends State<_WideLayout>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 320),
    value: widget.panel == null ? 0 : 1,
  );
  late final _progress = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );
  late final _slide = Tween(
    begin: const Offset(0.035, 0),
    end: Offset.zero,
  ).animate(_progress);
  late PlayerPanel? _builtPanel = widget.panel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context))
      _controller.value = widget.panel == null ? 0 : 1;
  }

  @override
  void didUpdateWidget(_WideLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panel == widget.panel) return;
    if (widget.panel case final panel?) {
      _builtPanel = panel;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    } else {
      (MediaQuery.disableAnimationsOf(context)
              ? _controller.animateTo(0, duration: Duration.zero)
              : _controller.reverse())
          .whenCompleteOrCancel(() {
            if (mounted && widget.panel == null)
              setState(() => _builtPanel = null);
          });
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final metadata = widget.metadata;
    final live = metadata.extras?['isLive'] == true;
    return Column(
      children: [
        const _CloseButton(),
        // The middle belongs to playback: notices go to the corner.
        const NoticeCorner(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final width = min<double>(380, c.maxWidth * 0.48 - 32);
              final playback = Center(
                child: SizedBox(
                  width: width,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Flexible(
                        child: LayoutBuilder(
                          builder: (context, art) => Center(
                            heightFactor: 1,
                            child: NowPlayingArtwork(
                              metadata: metadata,
                              size: min(width, art.maxHeight),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      NowPlayingTitle(
                        metadata: metadata,
                        titleSize: 22,
                        artistSize: 16,
                        spacing: 4,
                      ),
                      const SizedBox(height: 16),
                      if (!live) ...[
                        const PlayerTransport(iconSize: 38, miniIconSize: 20),
                      ],
                      const SizedBox(height: 8),
                      Center(child: widget.actions),
                      const SizedBox(height: 12),
                      if (supportsDesktopVolumeControl)
                        const Center(
                          child: DesktopVolumeControl(sliderWidth: 180),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              );
              final panelWidth = c.maxWidth * 0.52;
              final panel = _builtPanel == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        40,
                        0,
                        64,
                        20,
                      ),
                      child: AnimatedSwitcher(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 260),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, 0.035),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: _builtPanel == PlayerPanel.queue
                            ? const QueueWidget(
                                key: ValueKey('player-queue'),
                                embedded: true,
                              )
                            : LyricsPanel(
                                key: const ValueKey('player-lyrics'),
                                metadata: metadata,
                              ),
                      ),
                    );
              return AnimatedBuilder(
                animation: _progress,
                child: playback,
                builder: (context, playback) {
                  final shownWidth = panelWidth * _progress.value;
                  return Row(
                    children: [
                      SizedBox(width: c.maxWidth - shownWidth, child: playback),
                      if (_builtPanel != null)
                        SizedBox(
                          width: shownWidth,
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: AlignmentDirectional.centerStart,
                              minWidth: panelWidth,
                              maxWidth: panelWidth,
                              child: FadeTransition(
                                opacity: _progress,
                                child: SlideTransition(
                                  position: _slide,
                                  child: IgnorePointer(
                                    ignoring: widget.panel == null,
                                    child: panel,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
