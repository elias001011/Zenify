import 'dart:io';

import 'package:musify/services/common_services.dart';
import 'package:musify/services/moods/moods_preferences.dart';
import 'package:musify/services/moods/moods_service.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/utilities/media_duration.dart';

/// Where a playlist the user can export comes from.
enum ExportSource { likedSongs, custom, youtube, saved, zenify }

/// One thing in the library that holds songs and can become a CSV file.
typedef ExportEntry = ({String id, String title, ExportSource source});

const likedSongsExportId = 'liked-songs';

const _csvHeader = [
  'Song',
  'Artist',
  'Duration (ms)',
  'YouTube ID',
  'YouTube URL',
];

/// Everything in the library that holds songs, artists left out. The playlists
/// added from YouTube are looked up online for their names.
Future<List<ExportEntry>> exportableLibrary({
  required String likedSongsTitle,
}) async {
  final entries = <ExportEntry>[];
  final seen = <String>{};
  void add(Object? id, Object? title, ExportSource source) {
    final key = id?.toString() ?? '';
    if (key.isEmpty || !seen.add(key)) return;
    entries.add((id: key, title: title?.toString() ?? key, source: source));
  }

  if (userLikedSongsList.value.isNotEmpty) {
    add(likedSongsExportId, likedSongsTitle, ExportSource.likedSongs);
  }
  for (final playlist in getUserCustomPlaylists()) {
    add(playlist['ytid'], playlist['title'], ExportSource.custom);
  }
  for (final playlist in getLikedPlaylistItems()) {
    add(playlist['ytid'], playlist['title'], ExportSource.saved);
  }
  for (final id in savedZenifyPlaylists.value) {
    add(id, moodsService.cachedPlaylist(id)['title'], ExportSource.zenify);
  }
  for (final playlist in await getUserPlaylists()) {
    add((playlist as Map)['ytid'], playlist['title'], ExportSource.youtube);
  }
  return entries;
}

/// The songs of [entry], or null when they could not be loaded.
Future<List<Map>?> exportSongs(ExportEntry entry) async {
  try {
    final List? songs;
    switch (entry.source) {
      case ExportSource.likedSongs:
        songs = userLikedSongsList.value;
      case ExportSource.zenify:
        final cached = moodsService.cachedPlaylist(entry.id)['list'] as List;
        songs = cached.isNotEmpty
            ? cached
            : (await moodsService.playlist(entry.id))?['list'] as List?;
      default:
        songs = (await getPlaylistInfoForWidget(entry.id))?['list'] as List?;
    }
    return songs?.whereType<Map>().toList();
  } catch (_) {
    return null;
  }
}

/// Makes spreadsheets read the accents right.
final _byteOrderMark = String.fromCharCode(0xFEFF);

/// The CSV for [songs]. It has Song and Artist columns, like the files the
/// Spotify import reads, so what is exported here can be imported again.
String playlistCsv(Iterable<Map> songs) {
  final rows = [
    _csvHeader,
    for (final song in songs)
      if ((song['title']?.toString() ?? '').trim().isNotEmpty)
        [
          _csvField(song['title'].toString(), text: true),
          _csvField(song['artist']?.toString() ?? '', text: true),
          readMediaDuration(song['duration'])?.inMilliseconds.toString() ?? '',
          _csvField(song['ytid']?.toString() ?? ''),
          if (song['ytid'] case final String id when id.isNotEmpty)
            'https://music.youtube.com/watch?v=$id'
          else
            '',
        ],
  ];
  return '$_byteOrderMark${rows.map((row) => row.join(',')).join('\r\n')}\r\n';
}

/// Quotes what needs it. A [text] that starts like a formula (a title comes
/// from whoever uploaded the video) gets a leading quote, so a spreadsheet
/// shows it instead of running it.
String _csvField(String value, {bool text = false}) {
  final safe = text && RegExp(r'^[=+\-@\t\r]').hasMatch(value)
      ? "'$value"
      : value;
  return safe.contains(RegExp(r'[",\r\n]'))
      ? '"${safe.replaceAll('"', '""')}"'
      : safe;
}

final _windowsDeviceName = RegExp(
  r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])$',
  caseSensitive: false,
);

/// A file name for [title] that is safe on every system, not in [taken] and
/// not already in the folder ([exists]).
String csvFileName(
  String title,
  Set<String> taken, {
  bool Function(String name)? exists,
}) {
  final clean = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .trim()
      .replaceFirst(RegExp(r'[. ]+$'), '');
  var base = String.fromCharCodes(
    (clean.isEmpty ? 'playlist' : clean).runes.take(80),
  );
  if (_windowsDeviceName.hasMatch(base)) base = '_$base';
  var name = '$base.csv';
  for (
    var copy = 2;
    !taken.add(name.toLowerCase()) || (exists?.call(name) ?? false);
    copy++
  ) {
    name = '$base ($copy).csv';
  }
  return name;
}

/// Writes one CSV per entry into [directory], never over a file that is
/// already there, and returns the paths written with how many entries could
/// not be loaded or written.
Future<({List<String> files, int failed})> writePlaylistCsvs(
  Iterable<ExportEntry> entries,
  Directory directory,
) async {
  await directory.create(recursive: true);
  final taken = <String>{};
  final files = <String>[];
  var failed = 0;
  for (final entry in entries) {
    try {
      final songs = await exportSongs(entry);
      if (songs == null || songs.isEmpty) {
        failed++;
        continue;
      }
      final name = csvFileName(
        entry.title,
        taken,
        exists: (name) => File('${directory.path}/$name').existsSync(),
      );
      final file = File('${directory.path}/$name');
      await file.writeAsString(playlistCsv(songs));
      files.add(file.path);
    } catch (_) {
      failed++;
    }
  }
  return (files: files, failed: failed);
}
