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
import 'package:musify/services/common_services.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/platform_utils.dart';
import 'package:musify/widgets/flip_card.dart';
import 'package:musify/widgets/now_playing/wave_visualizer.dart';
import 'package:musify/widgets/song_artwork.dart';

/// The player's artwork. Tapping it flips it round, as in the original
/// Musify, to sound waves on the page itself, and back; on desktop it tilts gently after the mouse, the side
/// under it sinking in.
class NowPlayingArtwork extends StatefulWidget {
  const NowPlayingArtwork({
    super.key,
    required this.metadata,
    required this.size,
  });

  final MediaItem metadata;
  final double size;

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

    final content = ValueListenableBuilder<bool>(
      valueListenable: showPlayerVisualizer,
      builder: (context, visualizer, _) => GestureDetector(
        onTap: () => setPlayerVisualizer(!visualizer),
        child: FlipCard(
          flipped: visualizer,
          frontWidget: artwork,
          backWidget: SizedBox.square(
            dimension: size,
            // The card builds only the side in view, so the waves listen
            // to playback only while they show.
            child: Center(child: WaveVisualizer(size: size * 0.8)),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        if (isDesktopPlatform) _tilted(content) else content,
        // Kept flat over the tilt, where small text would shimmer; it leaves
        // with a fade when the artwork flips to the waves.
        Positioned(
          right: 10,
          bottom: 10,
          child: ValueListenableBuilder<bool>(
            valueListenable: showPlayerVisualizer,
            builder: (context, visualizer, child) => AnimatedOpacity(
              opacity: visualizer ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: child,
            ),
            child: IgnorePointer(
              child: _AudioQualityBadge(metadata: widget.metadata),
            ),
          ),
        ),
      ],
    );
  }

  /// On desktop, the artwork tilts gently after the mouse.
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

typedef _AudioQualityInfo = ({int bitrateKbps, String codec});

String _normalizeCodec(String codec) => switch (codec) {
  final c when c.startsWith('opus') => 'Opus',
  final c when c.startsWith('mp4a') => 'AAC',
  final c => c,
};

/// Resolves a song's stored or playback audio quality, or null if unavailable.
Future<_AudioQualityInfo?> _resolveAudioQuality(String ytid) async {
  final offlineSong = getOfflineSongByYtid(ytid);
  final offlineBitrate = offlineSong['audioBitrateKbps'] as int?;
  final offlineCodec = offlineSong['audioCodec'] as String?;
  if (offlineBitrate != null && offlineCodec != null) {
    return (bitrateKbps: offlineBitrate, codec: _normalizeCodec(offlineCodec));
  }
  if (offlineSong.isNotEmpty || offlineMode.value) return null;

  // Free for a song that is playing: the stream it picked is already resolved
  // and cached, so this reads it back instead of asking YouTube again.
  final stream = await fetchBestAudioStream(ytid);
  if (stream == null) return null;

  return (
    bitrateKbps: stream.bitrate.kiloBitsPerSecond.round(),
    codec: _normalizeCodec(stream.audioCodec),
  );
}

/// Shows the current song's resolved audio bitrate and codec.
class _AudioQualityBadge extends StatefulWidget {
  const _AudioQualityBadge({required this.metadata});
  final MediaItem metadata;

  @override
  State<_AudioQualityBadge> createState() => _AudioQualityBadgeState();
}

class _AudioQualityBadgeState extends State<_AudioQualityBadge> {
  String? _resolvedYtid;
  Future<_AudioQualityInfo?>? _infoFuture;

  @override
  void initState() {
    super.initState();
    _resolveIfNeeded();
  }

  @override
  void didUpdateWidget(_AudioQualityBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolveIfNeeded();
  }

  void _resolveIfNeeded() {
    final ytid = widget.metadata.extras?['ytid']?.toString();
    if (ytid == _resolvedYtid) return;
    _resolvedYtid = ytid;

    final shouldResolve =
        showAudioQualityBadge.value && ytid != null && ytid.isNotEmpty;
    _infoFuture = shouldResolve ? _resolveAudioQuality(ytid) : null;
  }

  @override
  Widget build(BuildContext context) {
    final infoFuture = _infoFuture;
    if (infoFuture == null) return const SizedBox.shrink();

    return FutureBuilder<_AudioQualityInfo?>(
      future: infoFuture,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (info == null) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${info.bitrateKbps} kbps • ${info.codec}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }
}
