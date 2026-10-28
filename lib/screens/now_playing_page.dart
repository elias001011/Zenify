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
import 'package:musify/extensions/l10n.dart';
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

  static bool _isWide(Size size) => size.width >= 900 && size.height >= 560;

  void _onPanel(PlayerPanel panel, MediaItem metadata) {
    if (_isWide(MediaQuery.sizeOf(context))) {
      setState(() => _panel = _panel == panel ? null : panel);
      return;
    }
    showCustomBottomSheet(
      context,
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
      return metadata.extras?['artWorkPath']?.toString();
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
            onPanel: (panel) => _onPanel(panel, metadata),
          );
          return Stack(
            children: [
              Positioned.fill(
                child: PageGlow(source: _artworkSource(metadata)),
              ),
              SafeArea(
                child: _isWide(MediaQuery.sizeOf(context))
                    ? _WideLayout(
                        metadata: metadata,
                        actions: actions,
                        panel: _panel,
                        onClosePanel: () => setState(() => _panel = null),
                      )
                    : _CompactLayout(metadata: metadata, actions: actions),
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

/// Phones: the artwork, the song and playback, then the action bar.
class _CompactLayout extends StatelessWidget {
  const _CompactLayout({required this.metadata, required this.actions});

  final MediaItem metadata;
  final Widget actions;

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

    return Column(
      children: [
        const _CloseButton(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: size.width > size.height
                ? Row(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, c) => artwork(c, 1),
                        ),
                      ),
                      const SizedBox(width: 24),
                      Expanded(child: controls),
                    ],
                  )
                : Column(
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

/// Desktop and tablets: the artwork takes the stage, with a bar below for
/// the song, playback and actions. Queue and lyrics open beside it.
class _WideLayout extends StatelessWidget {
  const _WideLayout({
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
                  builder: (context, c) => Center(
                    child: NowPlayingArtwork(
                      metadata: metadata,
                      size: min(min(c.maxHeight * 0.86, c.maxWidth * 0.7), 620),
                    ),
                  ),
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
                          child: _SidePanel(
                            panel: panel,
                            metadata: metadata,
                            onClose: onClosePanel,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: FloatingSurface(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: NowPlayingTitle(
                    metadata: metadata,
                    titleSize: 18,
                    artistSize: 14,
                    spacing: 2,
                    alignment: CrossAxisAlignment.start,
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: isLive
                      ? const SizedBox.shrink()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PlayerControlButtons(
                              metadata: metadata,
                              iconSize: 36,
                              miniIconSize: 20,
                            ),
                            const PositionSlider(),
                          ],
                        ),
                ),
                Expanded(
                  flex: 3,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: actions,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.panel,
    required this.metadata,
    required this.onClose,
  });

  final PlayerPanel panel;
  final MediaItem metadata;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return FloatingSurface(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(
              children: [
                // The queue has a header of its own.
                Expanded(
                  child: panel == PlayerPanel.lyrics
                      ? Text(
                          context.l10n!.lyrics,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        )
                      : const SizedBox.shrink(),
                ),
                IconButton(
                  icon: const Icon(FluentIcons.dismiss_24_regular),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: panel == PlayerPanel.queue
                ? const QueueWidget()
                : LyricsPanel(metadata: metadata),
          ),
        ],
      ),
    );
  }
}
