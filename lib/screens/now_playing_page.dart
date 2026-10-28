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
import 'package:musify/utilities/flutter_bottom_sheet.dart';
import 'package:musify/widgets/artwork_glow.dart';
import 'package:musify/widgets/floating_surface.dart';
import 'package:musify/widgets/now_playing/lyrics_panel.dart';
import 'package:musify/widgets/now_playing/now_playing_artwork.dart';
import 'package:musify/widgets/now_playing/now_playing_controls.dart';
import 'package:musify/widgets/now_playing/player_actions.dart';
import 'package:musify/widgets/position_slider.dart';
import 'package:musify/widgets/queue_list_view.dart';
import 'package:musify/widgets/song_artwork.dart';

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
  /// Open beside the player (wide layout only). Closed by default.
  PlayerPanel? _panel;
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

  static bool _isWide(Size size) => size.width >= 900 && size.height >= 560;

  /// [sheetContext] sits under the page's scaffold, which sheets open in.
  void _onPanel(
    PlayerPanel panel,
    MediaItem metadata,
    BuildContext sheetContext,
  ) {
    final size = MediaQuery.sizeOf(context);
    // Wide players open panels beside the artwork; upright phones show the
    // lyrics in place of it, as Tidal does.
    if (_isWide(size) ||
        (panel == PlayerPanel.lyrics && size.height > size.width)) {
      setState(() => _panel = _panel == panel ? null : panel);
      return;
    }
    showCustomBottomSheet(
      sheetContext,
      panel == PlayerPanel.queue
          ? const QueueWidget(isBottomSheet: true)
          : SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.6,
              child: LyricsPanel(metadata: metadata),
            ),
    );
  }

  /// The artwork as [PageGlow] reads it: a file path or a URL.
  static String? _artworkSource(MediaItem metadata) {
    final uri = metadata.artUri;
    if (uri?.scheme == 'file')
      return metadata.extras?['artWorkPath']?.toString() ?? uri!.toFilePath();
    return uri?.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: StreamBuilder<MediaItem?>(
        stream: audioHandler.mediaItem,
        builder: (context, snapshot) {
          final metadata = snapshot.data;
          if (metadata == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final actions = PlayerActions(
            metadata: metadata,
            panel: _panel,
            onPanel: (panel, sheetContext) =>
                _onPanel(panel, metadata, sheetContext),
          );
          return Stack(
            children: [
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: _backgroundVisible ? 1 : 0,
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  child: PageGlow(source: _artworkSource(metadata)),
                ),
              ),
              SafeArea(
                child: _isWide(MediaQuery.sizeOf(context))
                    ? _WideLayout(
                        metadata: metadata,
                        actions: actions,
                        panel: _panel,
                      )
                    : _CompactLayout(
                        metadata: metadata,
                        actions: actions,
                        lyrics: _panel == PlayerPanel.lyrics,
                        onCloseLyrics: () => setState(() => _panel = null),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
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
/// [lyrics] on, the song moves up to a small header and the lyrics take the
/// artwork's place.
class _CompactLayout extends StatelessWidget {
  const _CompactLayout({
    required this.metadata,
    required this.actions,
    required this.lyrics,
    required this.onCloseLyrics,
  });

  final MediaItem metadata;
  final Widget actions;
  final bool lyrics;
  final VoidCallback onCloseLyrics;

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
            audioId: metadata.extras?['ytid'],
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

    final Widget stage;
    if (size.width > size.height) {
      stage = Row(
        children: [
          Expanded(
            child: LayoutBuilder(builder: (context, c) => artwork(c, 1)),
          ),
          const SizedBox(width: 24),
          Expanded(child: controls),
        ],
      );
    } else {
      stage = AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: lyrics
            ? _LyricsStage(
                key: const ValueKey('lyrics'),
                metadata: metadata,
                onClose: onCloseLyrics,
                iconSize: iconSize * 0.85,
                miniIconSize: miniIconSize,
              )
            : Column(
                key: const ValueKey('artwork'),
                children: [
                  Expanded(
                    flex: 5,
                    child: LayoutBuilder(
                      builder: (context, c) => artwork(c, 0.92),
                    ),
                  ),
                  Expanded(flex: 4, child: controls),
                ],
              ),
      );
    }

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

/// The phone player with lyrics: the song small on top, the lyrics, then
/// playback. Tapping the song goes back to the artwork.
class _LyricsStage extends StatelessWidget {
  const _LyricsStage({
    super.key,
    required this.metadata,
    required this.onClose,
    required this.iconSize,
    required this.miniIconSize,
  });

  final MediaItem metadata;
  final VoidCallback onClose;
  final double iconSize;
  final double miniIconSize;

  static const double _artworkSize = 56;

  @override
  Widget build(BuildContext context) {
    final isLive = metadata.extras?['isLive'] ?? false;
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onClose,
          child: Row(
            children: [
              SongArtworkWidget(metadata: metadata, size: _artworkSize),
              const SizedBox(width: 14),
              Expanded(
                child: NowPlayingTitle(
                  metadata: metadata,
                  titleSize: 17,
                  artistSize: 14,
                  spacing: 2,
                  alignment: CrossAxisAlignment.start,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: LyricsPanel(metadata: metadata)),
        if (!isLive) ...[
          const PositionSlider(),
          PlayerControlButtons(
            metadata: metadata,
            iconSize: iconSize,
            miniIconSize: miniIconSize,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Desktop and tablets, as Tidal: the artwork with the song, playback and
/// actions under it in one column, centred; queue and lyrics open beside it.
class _WideLayout extends StatelessWidget {
  const _WideLayout({
    required this.metadata,
    required this.actions,
    required this.panel,
  });

  final MediaItem metadata;
  final Widget actions;
  final PlayerPanel? panel;

  /// Height the song, playback and actions take under the artwork.
  static const double _below = 344;

  @override
  Widget build(BuildContext context) {
    final isLive = metadata.extras?['isLive'] ?? false;
    final panel = this.panel;

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
                      c.maxHeight - _below,
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
                              const PositionSlider(),
                              PlayerControlButtons(
                                metadata: metadata,
                                iconSize: 40,
                                miniIconSize: 20,
                              ),
                            ],
                            const SizedBox(height: 16),
                            PlayerActionBar(child: actions),
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
      child: panel == PlayerPanel.queue
          ? const QueueWidget()
          : LyricsPanel(metadata: metadata),
    );
  }
}
