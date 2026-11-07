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
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/platform_utils.dart';
import 'package:musify/widgets/flip_card.dart';
import 'package:musify/widgets/now_playing/wave_visualizer.dart';
import 'package:musify/widgets/song_artwork.dart';

/// The player's artwork. Tapping it flips it round, as in the original
/// Musify, to sound waves on the page itself, and back. Each platform keeps
/// the motion that suits its pointer: on phones the cover slides the way a
/// song goes; on desktop it tilts gently after the mouse, the side under it
/// sinking in.
class NowPlayingArtwork extends StatefulWidget {
  const NowPlayingArtwork({
    super.key,
    required this.metadata,
    required this.size,
    this.slideOnSkip = true,
  });

  final MediaItem metadata;
  final double size;

  /// Whether the cover slides when the song changes (phones only). Off while
  /// it is the small cover in the header over the lyrics or the queue, where a
  /// slide across the screen would look like it came from nowhere.
  final bool slideOnSkip;

  @override
  State<NowPlayingArtwork> createState() => _NowPlayingArtworkState();
}

class _NowPlayingArtworkState extends State<NowPlayingArtwork> {
  static const _radius = 24.0;

  /// -1 to 1 on each axis from the centre, while the mouse is over it.
  final _tilt = ValueNotifier<Offset>(Offset.zero);

  void _onHover(PointerHoverEvent event) {
    final half = widget.size / 2;
    _tilt.value = Offset(
      ((event.localPosition.dx - half) / half).clamp(-1, 1),
      ((event.localPosition.dy - half) / half).clamp(-1, 1),
    );
  }

  @override
  void dispose() {
    _tilt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;

    final artwork = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: SongArtworkWidget(
        metadata: widget.metadata,
        size: size,
        errorWidgetIconSize: size / 6,
        borderRadius: _radius,
      ),
    );
    final front = _SkipSlide(
      trackId: widget.metadata.id,
      enabled: widget.slideOnSkip && isMobilePlatform,
      child: artwork,
    );

    final content = ValueListenableBuilder<bool>(
      valueListenable: showPlayerVisualizer,
      builder: (context, visualizer, _) => GestureDetector(
        onTap: () => setPlayerVisualizer(!visualizer),
        child: FlipCard(
          flipped: visualizer,
          frontWidget: front,
          backWidget: SizedBox.square(
            dimension: size,
            // The card builds only the side in view, so the waves listen
            // to playback only while they show.
            child: Center(child: WaveVisualizer(size: size * 0.8)),
          ),
        ),
      ),
    );

    return isDesktopPlatform ? _tilted(content) : content;
  }

  Widget _tilted(Widget content) {
    return MouseRegion(
      onHover: _onHover,
      onExit: (_) => _tilt.value = Offset.zero,
      child: ValueListenableBuilder<Offset>(
        valueListenable: _tilt,
        // Tilting moves the artwork without repainting it.
        child: RepaintBoundary(child: content),
        builder: (context, target, child) => TweenAnimationBuilder<Offset>(
          tween: Tween(end: target),
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
          builder: (context, tilt, child) => Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              // Signs make the side under the mouse recede.
              ..rotateX(tilt.dy * 0.07)
              ..rotateY(-tilt.dx * 0.07),
            child: child,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Which way the next song change goes: 1 forward, -1 back. The skip buttons
/// set it just before they skip, and the cover takes it on the change.
int skipDirection = 1;

/// Runs [skip] so the cover moves [direction] when the song changes. A
/// successful skip drops the direction once that change is drawn; a failed one
/// drops it at once, so it cannot reach a later change.
Future<void> skipWithDirection(
  int direction,
  Future<void> Function() skip,
) async {
  skipDirection = direction;
  try {
    await skip();
  } catch (_) {
    skipDirection = 1;
    rethrow;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) => skipDirection = 1);
}

/// Slides the cover the way the song goes, as Spotify does: the new cover
/// comes in from the side of the skip and the old one leaves to the other.
class _SkipSlide extends StatefulWidget {
  const _SkipSlide({
    required this.trackId,
    required this.enabled,
    required this.child,
  });

  final String trackId;
  final bool enabled;
  final Widget child;

  @override
  State<_SkipSlide> createState() => _SkipSlideState();
}

class _SkipSlideState extends State<_SkipSlide> {
  /// 1 forward, -1 back. Read while the cover moves.
  int _direction = 1;

  @override
  void didUpdateWidget(_SkipSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trackId != oldWidget.trackId) {
      _direction = skipDirection;
      skipDirection = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      // No time to move: the new cover simply takes the place.
      duration: widget.enabled
          ? const Duration(milliseconds: 300)
          : Duration.zero,
      transitionBuilder: (child, animation) {
        if (!widget.enabled) return child;
        final incoming = child.key == ValueKey(widget.trackId);
        return AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            // Linear on purpose: both covers ride one rail at a steady speed.
            // The rail's step is a whole screen, so the leaving cover is
            // off screen before the arriving one comes in, and they never meet.
            final t = animation.value;
            final shift = incoming ? 1 - t : t - 1;
            final step = MediaQuery.sizeOf(context).width;
            return Transform.translate(
              offset: Offset(shift * _direction * step, 0),
              child: child,
            );
          },
        );
      },
      // Its own layer: the slide moves the picture and its wide shadow as
      // they were drawn, instead of drawing them again on every frame.
      child: KeyedSubtree(
        key: ValueKey(widget.trackId),
        child: RepaintBoundary(child: widget.child),
      ),
    );
  }
}
