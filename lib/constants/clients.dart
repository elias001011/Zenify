import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Clients tried in order - the next one is used only if the previous fails
const fallbackClients = [YoutubeApiClient.visionOs, YoutubeApiClient.android];

// Client that produced the stream URL of each song, so playback can send
// the matching headers.
final Map<String, YoutubeApiClient> _songClients = {};

Future<StreamManifest> getManifestWithFallback(
  YoutubeExplode yt,
  String songId, {
  required Duration timeout,
}) async {
  Object? lastError;
  StackTrace? lastStack;

  for (final client in fallbackClients) {
    try {
      final manifest = await yt.videos.streams
          .getManifest(songId, ytClients: [client])
          .timeout(timeout);
      if (manifest.audioOnly.isEmpty) {
        throw VideoUnavailableException('No audio streams for "$songId"');
      }
      _songClients[songId] = client;
      return manifest;
    } catch (e, s) {
      lastError = e;
      lastStack = s;
    }
  }

  Error.throwWithStackTrace(lastError!, lastStack!);
}

/// Whether YouTube refused this device rather than the video: a video closed
/// to the country, or the check that asks to sign in to prove it is no bot.
/// Another address may get through; the song is not gone.
bool isDeviceBlock(VideoUnplayableException error) {
  final text = error.message.toLowerCase();
  return text.contains('country') ||
      text.contains('not a bot') ||
      text.contains('sign in');
}

/// Headers googlevideo.com expects for URLs minted by the client that served
/// [songId]; a mismatched User-Agent can cause HTTP 403.
Map<String, String> streamPlaybackHeaders(String? songId) {
  final client = _songClients[songId] ?? fallbackClients.first;
  final userAgent = client.payload['context']?['client']?['userAgent'];
  return {
    if (userAgent is String) 'user-agent': userAgent,
    for (final entry in client.headers.entries) entry.key: '${entry.value}',
  };
}
