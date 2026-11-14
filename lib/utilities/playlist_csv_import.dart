import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// A CSV row and its original position, used to preserve playlist order.
typedef PlaylistCsvRow = ({
  int index,
  String title,
  String artist,
  String? ytid,
});

/// Why a file gave no rows.
enum PlaylistCsvProblem {
  /// It has no song column or no artist column.
  invalid,

  /// It has a header only, or no row with a song name.
  empty,
}

List<List<String>> parseCsv(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;

  for (var index = 0; index < input.length; index++) {
    final character = input[index];
    if (character == '"') {
      if (quoted && index + 1 < input.length && input[index + 1] == '"') {
        field.write('"');
        index++;
      } else if (quoted || field.isEmpty) {
        quoted = !quoted;
      } else {
        // A quote inside an unquoted field is just text.
        field.write(character);
      }
    } else if (character == ',' && !quoted) {
      row.add(field.toString());
      field = StringBuffer();
    } else if ((character == '\n' || character == '\r') && !quoted) {
      if (character == '\r' &&
          index + 1 < input.length &&
          input[index + 1] == '\n') {
        index++;
      }
      row.add(field.toString());
      field = StringBuffer();
      if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
      row = <String>[];
    } else {
      field.write(character);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    if (row.any((value) => value.trim().isNotEmpty)) rows.add(row);
  }
  return rows;
}

/// The songs of the parsed [records] (the first one is the header), or the
/// [PlaylistCsvProblem] that stops the import.
({PlaylistCsvProblem? problem, List<PlaylistCsvRow> rows}) playlistCsvRows(
  List<List<String>> records,
) {
  if (records.length < 2) {
    return (problem: PlaylistCsvProblem.empty, rows: const []);
  }
  final headers = records.first
      .map((header) => header.replaceFirst('\ufeff', '').trim().toLowerCase())
      .toList();
  bool isNameColumn(String header) =>
      !header.contains('id') &&
      !header.contains('uri') &&
      !header.contains('url') &&
      !header.contains('genre');
  final songIndex = headers.indexWhere(
    (header) =>
        (header.contains('song') || header.contains('track')) &&
        isNameColumn(header),
  );
  final artistIndex = headers.indexWhere(
    (header) => header.contains('artist') && isNameColumn(header),
  );
  if (songIndex == -1 || artistIndex == -1) {
    return (problem: PlaylistCsvProblem.invalid, rows: const []);
  }

  // Only Zenify's own files have this column.
  final idIndex = headers.indexOf('youtube id');

  final songs = records.skip(1).where((row) {
    return row.length > songIndex &&
        row.length > artistIndex &&
        row[songIndex].trim().isNotEmpty;
  }).toList();
  if (songs.isEmpty) return (problem: PlaylistCsvProblem.empty, rows: const []);

  return (
    problem: null,
    rows: [
      for (final (index, row) in songs.indexed)
        (
          index: index,
          title: _unprotected(row[songIndex]).trim(),
          artist: _unprotected(row[artistIndex]).trim(),
          ytid: idIndex != -1 && row.length > idIndex
              ? _validId(row[idIndex])
              : null,
        ),
    ],
  );
}

final _youtubeId = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// [cell] as a YouTube video id, or null when it is not one (a local file's
/// id, an empty cell).
String? _validId(String cell) {
  final id = cell.trim();
  return _youtubeId.hasMatch(id) ? id : null;
}

/// What the export put a quote before so that a spreadsheet would not run it
/// as a formula, as it was. A name that starts with a quote of its own, like
/// 'Til Tuesday, is left alone.
String _unprotected(String value) =>
    RegExp(r"^'[=+\-@\t\r]").hasMatch(value) ? value.substring(1) : value;

/// Finds the song of [row]: by its YouTube id when the file has one, else (or
/// when the id gives nothing) with [search]. The second value is `true` when
/// YouTube is rate-limiting this device, so the import can stop.
Future<(Map<String, dynamic>?, bool)> resolveImportRow(
  PlaylistCsvRow row, {
  required Future<Map?> Function(String ytid) byId,
  required Future<(Map<String, dynamic>?, bool)> Function(PlaylistCsvRow row)
  search,
}) async {
  if (row.ytid case final id?) {
    try {
      final song = await byId(id);
      if (song != null && song.isNotEmpty) {
        return (Map<String, dynamic>.from(song), false);
      }
    } on RequestLimitExceededException {
      return (null, true);
    } catch (_) {
      // The id is gone or cannot be read: look for the song by its name.
    }
  }
  return search(row);
}
