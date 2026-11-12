import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/screens/replace_review_page.dart';
import 'package:musify/services/artist_service.dart' show ytMusicClient;
import 'package:musify/services/common_services.dart' show getSongDetails;
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/song_replacement.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/formatter.dart';
import 'package:musify/utilities/playlist_csv_import.dart';
import 'package:musify/utilities/url_launcher.dart';
import 'package:musify/widgets/floating_island.dart';
import 'package:musify/widgets/mini_player.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class ImportSpotifyPlaylistPage extends StatefulWidget {
  const ImportSpotifyPlaylistPage({super.key});

  @override
  State<ImportSpotifyPlaylistPage> createState() =>
      _ImportSpotifyPlaylistPageState();
}

class _ImportSpotifyPlaylistPageState extends State<ImportSpotifyPlaylistPage> {
  // Shared across page instances so navigating away and reopening the page
  // can't spawn a second import running concurrently with the first.
  static bool _importRunning = false;

  // Limit concurrency and leave a short pause between batches.
  static const _batchSize = 12;
  static const _batchPause = Duration(milliseconds: 150);

  final _csvController = TextEditingController();
  final _playlistNameController = TextEditingController();
  bool _isImporting = false;
  String? _fileName;
  int _processedCount = 0;
  int _totalCount = 0;

  @override
  void dispose() {
    _csvController.dispose();
    _playlistNameController.dispose();
    super.dispose();
  }

  Future<void> _chooseFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result.isEmpty || !mounted) return;

    final file = result.single;
    final path = file.path;
    if (path == null) return;
    _csvController.text = await File(path).readAsString();
    if (!mounted) return;
    setState(() => _fileName = file.name);
  }

  Future<void> _importPlaylist() async {
    if (_isImporting) return;
    if (_importRunning) {
      showToast(context, context.l10n!.spotifyPlaylistAlreadyImporting);
      return;
    }
    final playlistName = _playlistNameController.text.trim();
    if (playlistName.isEmpty) {
      showToast(context, context.l10n!.enterPlaylistName);
      return;
    }
    final parsed = playlistCsvRows(parseCsv(_csvController.text));
    switch (parsed.problem) {
      case PlaylistCsvProblem.empty:
        showToast(context, context.l10n!.spotifyPlaylistEmpty);
        return;
      case PlaylistCsvProblem.invalid:
        showToast(context, context.l10n!.spotifyPlaylistInvalid);
        return;
      case null:
        break;
    }
    final rows = parsed.rows;

    _importRunning = true;
    setState(() {
      _isImporting = true;
      _processedCount = 0;
      _totalCount = rows.length;
    });

    // Key results by their CSV position so retry results remain ordered.
    final foundByIndex = <int, Map>{};
    List<PlaylistCsvRow> missingRows;
    var rateLimited = false;
    var notSearched = <String>{};
    try {
      final firstPass = await _searchBatch(
        rows,
        onProgress: (n) {
          if (mounted) setState(() => _processedCount += n);
        },
      );
      foundByIndex.addAll(firstPass.found);
      missingRows = firstPass.missing;
      rateLimited = firstPass.rateLimited;

      // What YouTube Music did not find is looked for on YouTube: asking
      // YouTube Music again would fail again. Not while YouTube is limiting
      // this device.
      if (!rateLimited && missingRows.isNotEmpty) {
        // Include this work in the progress total.
        if (mounted) setState(() => _totalCount += missingRows.length);
        final fallback = await searchOnYoutube(
          [for (final row in missingRows) _asSong(row)],
          held: {
            for (final song in foundByIndex.values) song['ytid'].toString(),
          },
          onSearched: () {
            if (mounted) setState(() => _processedCount++);
          },
        );
        notSearched = fallback.notSearched;
        for (final row in missingRows) {
          if (fallback.found['file:${row.index}'] case final song?) {
            foundByIndex[row.index] = song;
          }
        }
        missingRows = [
          for (final row in missingRows)
            if (!foundByIndex.containsKey(row.index)) row,
        ];
      }
    } finally {
      _importRunning = false;
    }

    final foundSongs = [
      for (final row in rows)
        if (foundByIndex[row.index] case final song?) song,
    ];

    if (!mounted) return;
    final (_, playlistId) = createCustomPlaylist(playlistName, null, context);
    addSongsInCustomPlaylist(context, playlistId, foundSongs);
    setState(() => _isImporting = false);

    // Only what both searches missed is left for the person: the playlist is
    // made with what was found, then each of these can be searched by hand,
    // copied or left out.
    var stillMissing = missingRows;
    var imported = foundSongs.length;
    if (missingRows.isNotEmpty && !rateLimited) {
      final picked = await Navigator.of(context).push<Map<String, Map>>(
        MaterialPageRoute(
          builder: (_) => ReplaceReviewPage(
            kind: ReviewKind.missing,
            plan: ReplacementPlan(
              songs: [for (final row in missingRows) _asSong(row)],
              found: const {},
              playlistIds: {playlistId},
              held: songIdsOf([
                {'list': foundSongs},
              ]),
              notSearched: notSearched,
            ),
          ),
        ),
      );
      if (picked != null && picked.isNotEmpty && mounted) {
        addSongsInCustomPlaylist(context, playlistId, picked.values.toList());
        imported += picked.length;
        stillMissing = [
          for (final row in missingRows)
            if (!picked.containsKey('file:${row.index}')) row,
        ];
      }
    }

    if (!mounted) return;
    final resultText = rateLimited
        ? '${context.l10n!.spotifyPlaylistImportFailed}\n${context.l10n!.spotifyPlaylistImportResult(imported, rows.length)}'
        : context.l10n!.spotifyPlaylistImportResult(imported, rows.length);
    if (stillMissing.isNotEmpty) {
      final missingText = stillMissing
          .map((row) => '${row.title} - ${row.artist}')
          .join('\n');
      if (mounted) {
        showToastWithButton(
          context,
          '$resultText\n${context.l10n!.spotifyPlaylistMissingSongs}',
          context.l10n!.copy,
          () => Clipboard.setData(ClipboardData(text: missingText)),
          duration: const Duration(seconds: 8),
          icon: FluentIcons.warning_24_regular,
        );
      }
    } else {
      showToast(context, resultText);
    }
  }

  /// A row of the file as a song, the way the search and the review take it.
  Map<String, dynamic> _asSong(PlaylistCsvRow row) => {
    'ytid': 'file:${row.index}',
    'title': row.title,
    'artist': row.artist,
  };

  /// Resolves [rows] in batches and stops when rate limiting is detected.
  /// Results are keyed by the rows' original positions for retry merging.
  Future<
    ({Map<int, Map> found, List<PlaylistCsvRow> missing, bool rateLimited})
  >
  _searchBatch(
    List<PlaylistCsvRow> rows, {
    required void Function(int processedCount) onProgress,
  }) async {
    final found = <int, Map>{};
    final missing = <PlaylistCsvRow>[];
    for (var i = 0; i < rows.length; i += _batchSize) {
      final batch = rows.skip(i).take(_batchSize).toList();
      final batchResults = await Future.wait(
        batch.map((row) async {
          final (match, wasRateLimited) = await resolveImportRow(
            row,
            byId: _songById,
            search: (r) => _findSongWithRetry(
              '${r.title} ${r.artist}',
              expectedArtist: r.artist,
              expectedTitle: r.title,
            ),
          );
          return (row, match, wasRateLimited);
        }),
      );
      var batchRateLimited = false;
      for (final (row, match, wasRateLimited) in batchResults) {
        if (wasRateLimited) batchRateLimited = true;
        if (match == null) {
          missing.add(row);
        } else {
          found[row.index] = match;
        }
      }
      onProgress(batchResults.length);
      if (batchRateLimited) {
        missing.addAll(rows.skip(i + _batchSize));
        return (found: found, missing: missing, rateLimited: true);
      }
      await Future.delayed(_batchPause);
    }
    return (found: found, missing: missing, rateLimited: false);
  }

  /// The song with YouTube id [ytid]. A rate limit gets the same single
  /// retry as a search; the second one is left to the caller.
  Future<Map?> _songById(String ytid) async {
    try {
      return await getSongDetails(0, ytid);
    } on RequestLimitExceededException {
      await Future.delayed(const Duration(seconds: 2));
      return getSongDetails(0, ytid);
    }
  }

  /// Returns the best match for [query], or `null` if none was found.
  /// The second value is `true` when YouTube is actively rate-limiting this
  /// device, so the caller can stop the whole import instead of retrying
  /// every remaining song for minutes on end.
  Future<(Map<String, dynamic>?, bool)> _findSongWithRetry(
    String query, {
    String? expectedArtist,
    String? expectedTitle,
  }) async {
    const maxAttempts = 2;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final video = await ytMusicClient.music.searchSong(
          query,
          expectedArtist: expectedArtist,
          expectedTitle: expectedTitle,
        );
        if (video == null) return (null, false);
        return (Map<String, dynamic>.from(returnSongLayout(0, video)), false);
      } on RequestLimitExceededException {
        // A single short retry for a transient hiccup; a second hit means
        // it's a genuine, sustained block.
        if (attempt == maxAttempts - 1) return (null, true);
        await Future.delayed(const Duration(seconds: 2));
      } catch (e, stackTrace) {
        if (attempt == maxAttempts - 1) {
          logger.log(
            'Error searching Spotify import match for "$query"',
            error: e,
            stackTrace: stackTrace,
          );
          return (null, false);
        }
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }
    return (null, false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return IslandScaffold(
      title: context.l10n!.importSpotifyPlaylistTitle,
      body: SingleChildScrollView(
        padding: readableInset(
          context,
          const EdgeInsets.fromLTRB(16, 16, 16, 32),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.l10n!.importSpotifyPlaylistInstructions),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => launchURL(
                Uri.parse('https://www.chosic.com/spotify-playlist-exporter/'),
              ),
              icon: const Icon(FluentIcons.open_24_regular),
              label: Text(context.l10n!.openChosicExporter),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _isImporting ? null : _chooseFile,
              icon: const Icon(FluentIcons.document_add_24_regular),
              label: Text(_fileName ?? context.l10n!.chooseCsvFile),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _playlistNameController,
              enabled: !_isImporting,
              decoration: InputDecoration(
                labelText: '${context.l10n!.playlistName} *',
                hintText: context.l10n!.spotifyPlaylistNameHint,
                filled: true,
                fillColor: colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _csvController,
              enabled: !_isImporting,
              minLines: 10,
              maxLines: 18,
              decoration: InputDecoration(
                labelText: context.l10n!.pasteCsv,
                hintText: context.l10n!.spotifyCsvHint,
                alignLabelWithHint: true,
                filled: true,
                fillColor: colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isImporting ? null : _importPlaylist,
              icon: _isImporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(FluentIcons.arrow_upload_24_regular),
              label: Text(
                _isImporting
                    ? context.l10n!.spotifyPlaylistImporting
                    : context.l10n!.importPlaylist,
              ),
            ),
            if (_isImporting && _totalCount > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _processedCount / _totalCount,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n!.spotifyPlaylistProgress(
                  _processedCount,
                  _totalCount,
                ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: MiniPlayer.playerHeight + 24),
          ],
        ),
      ),
    );
  }
}
