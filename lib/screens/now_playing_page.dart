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
import 'package:musify/utilities/flutter_bottom_sheet.dart';
import 'package:musify/utilities/mediaitem.dart';
import 'package:musify/widgets/artwork_glow.dart';
import 'package:musify/widgets/floating_surface.dart';
import 'package:musify/widgets/now_playing/lyrics_panel.dart';
import 'package:musify/widgets/now_playing/now_playing_artwork.dart';
import 'package:musify/widgets/now_playing/now_playing_controls.dart';
import 'package:musify/widgets/now_playing/player_actions.dart';
import 'package:musify/widgets/position_slider.dart';
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
    _backgroundVisible =
        animation == null || animation.status == AnimationStatus.completed;
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

  /// [sheetContext] sits under the page's scaffold, which sheets open in.
  void _onPanel(
    PlayerPanel panel,
    MediaItem metadata,
    BuildContext sheetContext,
  ) {
    final layout = _PlayerLayout.of(MediaQuery.sizeOf(context));
    if (layout.showsInline(panel)) {
      setState(() => _panel = _panel == panel ? null : panel);
      return;
    }
    // Sideways lyrics still need more vertical space than the stage offers.
    if (_panel case final open? when !layout.showsInline(open)) {
      setState(() => _panel = null);
    }
    showCustomBottomSheet(
      sheetContext,
      SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: LyricsPanel(metadata: metadata),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Back closes a panel only when the layout shows it.
    final open = _panel;
    final panelShown =
        open != null &&
        _PlayerLayout.of(MediaQuery.sizeOf(context)).showsInline(open);
    return PopScope(
      canPop: !panelShown,
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
            final layout = _PlayerLayout.of(MediaQuery.sizeOf(context));
            // What shows depends on the layout now: a phone turned sideways
            // with the lyrics open shows none, and gets them back upright.
            final panel = _panel != null && layout.showsInline(_panel!)
                ? _panel
                : null;
            final actions = PlayerActions(
              metadata: metadata,
              panel: panel,
              onPanel: (panel, sheetContext) =>
                  _onPanel(panel, metadata, sheetContext),
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
    );
  }
}

enum _PlayerLayout {
  /// Desktop and tablets: queue and lyrics open beside the artwork.
  wide,

  /// Upright phones: lyrics and queue take the artwork's place.
  upright,

  /// Phones on their side: queue beside playback; lyrics open as a sheet.
  sideways;

  static _PlayerLayout of(Size size) => size.width >= 900 && size.height >= 560
      ? wide
      : size.height >= size.width
      ? upright
      : sideways;

  bool showsInline(PlayerPanel panel) =>
      this != sideways || panel == PlayerPanel.queue;
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
    final iconSize = size.width < 360 ? 36.0 : (size.width < 400 ? 40.0 : 44.0);
    final miniIconSize = size.width < 360 ? 18.0 : 22.0;

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
                  child: panel == PlayerPanel.queue
                      ? const QueueWidget(embedded: true)
                      : LayoutBuilder(builder: (context, c) => artwork(c, 1)),
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
            iconSize: iconSize,
            miniIconSize: miniIconSize,
          );

    return Column(
      children: [
        const _CloseButton(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: stage,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: PlayerActionBar(child: actions),
        ),
      ],
    );
  }
}

/// The upright phone player. Playback stays at the bottom; above it the
/// artwork and the song take the room, or, with a panel, the same artwork
/// shrinks into a header beside the song and the panel fills the rest, as
/// Tidal does. One layout that moves, not a second page over the first.
class _UprightStage extends StatefulWidget {
  const _UprightStage({
    required this.metadata,
    required this.panel,
    required this.onClosePanel,
    required this.iconSize,
    required this.miniIconSize,
  });

  final MediaItem metadata;
  final PlayerPanel? panel;
  final VoidCallback onClosePanel;
  final double iconSize;
  final double miniIconSize;

  @override
  State<_UprightStage> createState() => _UprightStageState();
}

class _UprightStageState extends State<_UprightStage>
    with SingleTickerProviderStateMixin {
  static const _headerSize = 56.0;
  static const _titleHeight = 72.0;
  static const _gap = 16.0;

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
                min(c.maxWidth * 0.92, c.maxHeight - _titleHeight - _gap * 2),
              );
              // The artwork and the song under it, centred together.
              final artOrigin = Offset(
                (c.maxWidth - artSize) / 2,
                (c.maxHeight - artSize - _gap - _titleHeight) / 2,
              );
              // Laid out once at full size and scaled, so the artwork keeps
              // its decoded image while it moves.
              final artwork = NowPlayingArtwork(
                metadata: metadata,
                size: artSize,
              );
              // Built once: the frames of the move only reposition and fade
              // them.
              final panel = _builtPanel == PlayerPanel.queue
                  ? const QueueWidget(embedded: true)
                  : LyricsPanel(metadata: metadata);
              final songTitle = Center(
                child: NowPlayingTitle(
                  metadata: metadata,
                  titleSize: getResponsiveTitleFontSize(screen),
                  artistSize: getResponsiveArtistFontSize(screen),
                  spacing: 6,
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
                  // Both titles follow the artwork: the one under it rises
                  // with it and leaves, the header's arrives beside it.
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
                          top: art.bottom + _gap,
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
          const SizedBox(height: 8),
          const PositionSlider(),
          PlayerControlButtons(
            metadata: metadata,
            iconSize: widget.iconSize,
            miniIconSize: widget.miniIconSize,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Desktop and tablets, as Tidal: the artwork with the song, playback and
/// actions under it in one column, centred; queue and lyrics open beside it.
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

class _WideLayoutState extends State<_WideLayout> {
  final _belowKey = GlobalKey();

  /// What the song, playback and actions take under the artwork, measured
  /// after each layout: it changes with the text size and for live radio.
  /// The last song's measure starts the next player, so only the first
  /// opening corrects itself; live radio, shorter, is left out of it, so the
  /// guess stays on the generous side and the first frame doesn't overflow.
  static double _lastSongBelow = 400;
  double _below = _lastSongBelow;

  void _measure(Duration _) {
    final height = _belowKey.currentContext?.size?.height;
    if (mounted && height != null && (height - _below).abs() > 0.5) {
      setState(() => _below = height);
      if (!(widget.metadata.extras?['isLive'] ?? false)) {
        _lastSongBelow = height;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final metadata = widget.metadata;
    final isLive = metadata.extras?['isLive'] ?? false;
    final panel = widget.panel;
    WidgetsBinding.instance.addPostFrameCallback(_measure);

    return Column(
      children: [
        const _CloseButton(),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final size = min(
                      c.maxHeight - _below - 16,
                      c.maxWidth - 64,
                    ).clamp(160.0, 560.0);
                    return Center(
                      child: SizedBox(
                        width: size,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            NowPlayingArtwork(metadata: metadata, size: size),
                            Column(
                              key: _belowKey,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 28),
                                NowPlayingTitle(
                                  metadata: metadata,
                                  titleSize: 24,
                                  artistSize: 16,
                                  spacing: 4,
                                  alignment: CrossAxisAlignment.start,
                                ),
                                const SizedBox(height: 12),
                                if (!isLive) ...[
                                  const PositionSlider(flush: true),
                                  PlayerControlButtons(
                                    metadata: metadata,
                                    iconSize: 40,
                                    miniIconSize: 20,
                                    flush: true,
                                  ),
                                ],
                                const SizedBox(height: 16),
                                PlayerActionBar(child: widget.actions),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: panel == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(0, 0, 16, 16),
                        child: SizedBox(
                          width: 400,
                          child: _SidePanel(panel: panel, metadata: metadata),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.panel, required this.metadata});

  final PlayerPanel panel;
  final MediaItem metadata;

  @override
  Widget build(BuildContext context) {
    return FloatingSurface(
      grouped: true,
      child: panel == PlayerPanel.queue
          ? const QueueWidget()
          : LyricsPanel(metadata: metadata),
    );
  }
}
