import 'package:audio_service/audio_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/common_services.dart';
import 'package:musify/services/local_files_service.dart';
import 'package:musify/services/settings_manager.dart';

typedef _AudioQualityInfo = ({int bitrateKbps, String codec});

String _normalizeCodec(String codec) => switch (codec) {
  final c when c.startsWith('opus') => 'Opus',
  final c when c.startsWith('mp4a') => 'AAC',
  final c => c,
};

/// Resolves a song's stored or playback audio quality, or null if unavailable.
Future<_AudioQualityInfo?> _resolveAudioQuality(String ytid) async {
  // A local file has no stream to ask about, and its id is never sent out.
  if (isLocalSongId(ytid)) return null;
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

String? _ytidOf(MediaItem? item) => item?.extras?['ytid']?.toString();

/// The playing song's audio bitrate and codec as a small tag, for the row of
/// times under the progress bar. It is about the stream, not the artwork, so
/// it looks the same on every layout. While the setting is off it is not even
/// built: nothing listens to the song and nothing is looked up.
class AudioQualityBadge extends StatelessWidget {
  const AudioQualityBadge({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: showAudioQualityBadge,
    builder: (context, enabled, _) => !enabled
        ? const SizedBox.shrink()
        : StreamBuilder<String?>(
            initialData: _ytidOf(audioHandler.mediaItem.valueOrNull),
            stream: audioHandler.mediaItem.map(_ytidOf).distinct(),
            builder: (context, snapshot) => _QualityTag(ytid: snapshot.data),
          ),
  );
}

class _QualityTag extends StatefulWidget {
  const _QualityTag({required this.ytid});

  final String? ytid;

  @override
  State<_QualityTag> createState() => _QualityTagState();
}

class _QualityTagState extends State<_QualityTag> {
  late Future<_AudioQualityInfo?>? _info = _resolve();

  Future<_AudioQualityInfo?>? _resolve() {
    final ytid = widget.ytid;
    return ytid == null || ytid.isEmpty ? null : _resolveAudioQuality(ytid);
  }

  @override
  void didUpdateWidget(_QualityTag oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ytid != oldWidget.ytid) _info = _resolve();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null) return const SizedBox.shrink();

    return FutureBuilder<_AudioQualityInfo?>(
      future: info,
      builder: (context, snapshot) {
        final quality = snapshot.data;
        if (quality == null) return const SizedBox.shrink();
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(7),
          ),
          // As tall as the times beside it, so the row never grows.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
            child: Text(
              '${quality.bitrateKbps} kbps • ${quality.codec}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }
}
