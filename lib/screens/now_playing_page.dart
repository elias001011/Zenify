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
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/mediaitem.dart';
import 'package:musify/widgets/artwork_glow.dart';
import 'package:musify/widgets/now_playing/lyrics_panel.dart';
import 'package:musify/widgets/now_playing/now_playing_artwork.dart';
import 'package:musify/widgets/now_playing/now_playing_controls.dart';
import 'package:musify/widgets/now_playing/player_actions.dart';
import 'package:musify/widgets/now_playing/player_chrome.dart';
import 'package:musify/widgets/queue_list_view.dart';
import 'package:musify/widgets/spinner.dart';

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

  /// Esc closes an open panel; with none open it is left for the app.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (_panel == null ||
        event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }
    setState(() => _panel = null);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final layout = _PlayerLayout.of(MediaQuery.sizeOf(context));
    return PlayerChrome(
      style: PlayerChromeStyle.plain,
      child: PopScope(
        // Back closes an open panel first, on every layout.
        canPop: _panel == null,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _panel = null);
        },
        child: Focus(
          autofocus: true,
          skipTraversal: true,
          onKeyEvent: _onKey,
          child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: StreamBuilder<MediaItem?>(
              initialData: audioHandler.mediaItem.value,
              stream: audioHandler.mediaItem,
              builder: (context, snapshot) {
                final metadata = snapshot.data;
                if (metadata == null) {
                  return const Spinner();
                }
                final panel = _panel;
                final actions = PlayerActions(
                  metadata: metadata,
                  panel: panel,
                  onPanel: _onPanel,
                  // Beside the song everywhere but on a phone on its side.
                  showAddToPlaylist: layout == _PlayerLayout.sideways,
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
                                onClosePanel: () =>
                                    setState(() => _panel = null),
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
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
    final isLive = metadata.extras?['isLive'] == true;
    final iconSize = size.width < 360 ? 42.0 : (size.width < 400 ? 48.0 : 52.0);
    final miniIconSize = size.width < 360 ? 20.0 : 24.0;
    const margin = 20.0;

    final controls = isLive
        // Just the buttons of a station, centred beside the cover.
        ? LayoutBuilder(
            builder: (context, c) => PlayerTransport(
              sizes: phoneButtonSizes(c.maxWidth),
              controlsOnly: true,
            ),
          )
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
        : _PlaybackStage(
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

/// What the player shows of the song, upright phones and the wide player
/// alike: the artwork over the whole width, the song and its playlist button
/// at its foot, then the progress bar and the buttons. On a phone the song and
/// playback sit together at the bottom, where the thumb is, and, with a panel,
/// the same artwork shrinks into a header beside the song and the panel fills
/// the rest, as Tidal does: one layout that moves, not a second page over the
/// first, and playback does not move with it. The wide player, whose panel
/// opens beside it, gives the stage [fill] false: it takes the height it needs
/// and the player centres it.
class _PlaybackStage extends StatefulWidget {
  const _PlaybackStage({
    required this.metadata,
    required this.buttonSizes,
    this.panel,
    this.onClosePanel,
    this.fill = true,
  });

  final MediaItem metadata;
  final PlayerButtonSizes buttonSizes;
  final PlayerPanel? panel;
  final VoidCallback? onClosePanel;
  final bool fill;

  @override
  State<_PlaybackStage> createState() => _PlaybackStageState();
}

class _PlaybackStageState extends State<_PlaybackStage>
    with SingleTickerProviderStateMixin {
  static const _headerSize = 56.0;

  // A phone has room to spare; the wide player takes only what the song needs,
  // so that its cover is as big as the window allows.
  double get _titleHeight =>
      (widget.fill ? 72 : 60) *
      max(1, MediaQuery.textScalerOf(context).scale(1));
  double get _gap => widget.fill ? 24 : 20;

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
  void didUpdateWidget(_PlaybackStage oldWidget) {
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
    final isLive = metadata.extras?['isLive'] == true;

    final area = LayoutBuilder(
      builder: (context, c) {
        // A radio station shows no name or artist under the cover, as in
        // Musify: the cover takes the room.
        final titleSpace = isLive ? 0.0 : _titleHeight + _gap;
        final artSize = max(
          _headerSize,
          min(c.maxWidth, c.maxHeight - titleSpace),
        );
        // What the artwork and the song leave of the height goes above
        // the artwork and between it and the song: the song stays at the
        // bottom, next to playback.
        final slack = widget.fill
            ? max<double>(0, c.maxHeight - (artSize + titleSpace))
            : 0.0;
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
        // The button to put the song in a playlist, or like it, sits
        // at the end of the song's line.
        final addToPlaylist = AddToPlaylistButton(
          metadata: metadata,
          beside: true,
        );
        final songTitle = Align(
          alignment: AlignmentDirectional.bottomStart,
          child: Row(
            children: [
              Expanded(
                child: NowPlayingTitle(
                  metadata: metadata,
                  titleSize: getResponsiveTitleFontSize(screen) + 2,
                  artistSize: getResponsiveArtistFontSize(screen) + 1,
                  spacing: 6,
                  alignment: CrossAxisAlignment.start,
                ),
              ),
              addToPlaylist,
            ],
          ),
        );
        final headerTitle = Align(
          alignment: AlignmentDirectional.centerStart,
          child: Row(
            children: [
              Expanded(
                child: NowPlayingTitle(
                  metadata: metadata,
                  titleSize: 17,
                  artistSize: 14,
                  spacing: 2,
                  alignment: CrossAxisAlignment.start,
                ),
              ),
              addToPlaylist,
            ],
          ),
        );

        final stage = AnimatedBuilder(
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
                if (under > 0 && !isLive)
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
                      child: AbsorbPointer(absorbing: t > 0, child: artwork),
                    ),
                  ),
                ),
              ],
            );
          },
        );
        return widget.fill
            ? stage
            : SizedBox(height: artSize + titleSpace, child: stage);
      },
    );
    return Column(
      mainAxisSize: widget.fill ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (widget.fill) Expanded(child: area) else Flexible(child: area),
        const SizedBox(height: 14),
        // A station has no progress bar, shuffle or repeat: just its buttons.
        PlayerTransport(sizes: widget.buttonSizes, controlsOnly: isLive),
        const SizedBox(height: 8),
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
    return Column(
      children: [
        const _CloseButton(),
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
                      // The phone's own stage, the panel beside it instead of
                      // over it.
                      Flexible(
                        child: _PlaybackStage(
                          metadata: metadata,
                          buttonSizes: phoneButtonSizes(width),
                          fill: false,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(child: widget.actions),
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
