import 'package:youtube_explode_dart/youtube_explode_dart.dart' show VideoId;

/// A pasted video link, never an eleven-character search term or playlist.
String? youtubeVideoIdFromUrl(String text) {
  final value = text.trim();
  final uri = Uri.tryParse(value.contains('://') ? value : 'https://$value');
  if (uri == null || !['http', 'https'].contains(uri.scheme)) return null;
  final host = uri.host.toLowerCase();
  if (host != 'youtu.be' &&
      host != 'youtube.com' &&
      !host.endsWith('.youtube.com'))
    return null;
  final path = uri.pathSegments;
  String? id;
  if (host == 'youtu.be' && path.length == 1) {
    id = path.first;
  } else if (uri.path == '/watch') {
    id = uri.queryParameters['v'];
  } else if (path.length == 2 &&
      ['embed', 'shorts', 'live'].contains(path.first)) {
    id = path[1];
  }
  return id != null && VideoId.validateVideoId(id) ? id : null;
}
