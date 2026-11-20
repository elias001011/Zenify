import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/mix_edits.dart';
import 'package:musify/services/mix_playlist_analysis.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/media_duration.dart';
import 'package:musify/widgets/mix_editor.dart';
import 'package:musify/widgets/song_bar.dart';

/// A real route: the playlist stays available alongside the transition on
/// desktop, and in a drawer on a phone. Selection never replaces playback.
class MixPage extends StatefulWidget {
  const MixPage({
    super.key,
    required this.playlist,
    required this.song,
    required this.next,
  });
  final String playlist;
  final Map song, next;
  @override
  State<MixPage> createState() => _MixPageState();
}

class _MixPageState extends State<MixPage> {
  List<Map> _songs = [];
  Map? _playlist;
  int _index = 0, _done = 0, _failed = 0;
  bool _analyzing = false, _cancel = false, _orderChanged = false;
  bool _savingOrder = false;
  String? _error;
  final _drafts = <String, MixEdit?>{};
  final _scaffold = GlobalKey<ScaffoldState>();
  bool get _canReorder => _playlist?['source'] == 'user-created';
  @override
  void initState() {
    super.initState();
    _songs = [widget.song, widget.next];
    unawaited(_load());
  }

  Future<void> _load() async {
    final playlist = await getPlaylistInfoForWidget(widget.playlist);
    if (!mounted || playlist == null) return;
    final songs = (playlist['list'] as List? ?? []).whereType<Map>().toList();
    if (songs.length < 2) return;
    var index = songs.indexWhere((s) => s['ytid'] == widget.song['ytid']);
    if (index < 0 || index >= songs.length - 1) index = 0;
    setState(() {
      _playlist = Map.of(playlist);
      _songs = songs;
      _index = index;
    });
  }

  @override
  void dispose() {
    _cancel = true;
    super.dispose();
  }

  Future<void> _select(int index) async {
    await audioHandler.stopMixPreview();
    if (!mounted) return;
    setState(() => _index = index.clamp(0, _songs.length - 2));
  }

  Future<void> _analyze() async {
    if (_analyzing) {
      _cancel = true;
      return;
    }
    setState(() {
      _analyzing = true;
      _cancel = false;
      _done = 0;
      _failed = 0;
    });
    final analyzer = audioHandler.mixAnalyzer;
    for (final song in List<Map>.of(_songs)) {
      if (_cancel || !mounted) break;
      final duration = readMediaDuration(song['duration']);
      var failed = false;
      {
        for (final tail in [false, true]) {
          if (_cancel || !mounted) break;
          if (analyzer.edge(song, tail: tail) == null) {
            final result = await analyzer.inspect(
              song,
              tail: tail,
              duration: duration,
            );
            failed = failed || result == null;
          }
        }
      }
      if (!mounted || _cancel) break;
      setState(() {
        _done++;
        if (failed) _failed++;
      });
    }
    if (mounted) setState(() => _analyzing = false);
    audioHandler.refreshMix();
  }

  Future<void> _saveOrder() async {
    if (!_canReorder || _savingOrder) return;
    setState(() {
      _savingOrder = true;
      _error = null;
    });
    try {
      await audioHandler.stopMixPreview();
      // Read again so a title or playlist update made elsewhere is preserved.
      final current = await getPlaylistInfoForWidget(widget.playlist);
      if (!mounted) return;
      if (current == null) throw StateError('Playlist unavailable');
      final currentIds = (current['list'] as List)
          .map((s) => s['ytid'])
          .toList();
      final originalIds = (_playlist!['list'] as List)
          .map((s) => s['ytid'])
          .toList();
      final ids = _songs.map((s) => s['ytid']).toList();
      if (!listEquals(currentIds, originalIds) ||
          currentIds.length != ids.length ||
          ids.toSet().length != ids.length ||
          !currentIds.every(ids.contains)) {
        await _load();
        if (mounted) {
          setState(() {
            _orderChanged = false;
            _error = context.l10n!.mixSaveFailed;
          });
        }
        return;
      }
      final latest = {
        for (final song in current['list'] as List) song['ytid']: song,
      };
      final reordered = [for (final id in ids) latest[id] as Map];
      if (!await replaceCustomPlaylist(widget.playlist, {
        ...current,
        'list': reordered,
      })) {
        throw StateError('Playlist unavailable');
      }
      if (mounted)
        setState(() {
          _orderChanged = false;
          _songs = reordered;
          _playlist = {...current, 'list': reordered};
        });
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n!.mixSaveFailed);
    } finally {
      if (mounted) setState(() => _savingOrder = false);
    }
  }

  void _reorder(int from, int to) {
    if (!_canReorder || _savingOrder || from == to) return;
    final selected = _songs[_index];
    final reordered = [..._songs];
    reordered.insert(to, reordered.removeAt(from));
    setState(() {
      _songs = reordered;
      _index = _songs.indexOf(selected).clamp(0, _songs.length - 2);
      _orderChanged = true;
    });
    unawaited(_saveOrder());
  }

  Future<void> _smartOrder() async {
    if (!_canReorder || _savingOrder) return;
    await audioHandler.stopMixPreview();
    if (!mounted) return;
    setState(() {
      _songs = orderMixSongs(_songs, audioHandler.mixAnalyzer);
      _index = 0;
      _orderChanged = true;
    });
  }

  Widget _tracks() => ListenableBuilder(
    listenable: audioHandler.mixAnalyzer.changes,
    builder: (context, _) => ReorderableListView.builder(
      buildDefaultDragHandles: false,
      onReorderItem: _reorder,
      itemCount: _songs.length,
      itemBuilder: (context, i) {
        final edge = audioHandler.mixAnalyzer.edge(_songs[i], tail: false);
        return Padding(
          key: ValueKey('mix-track-${_songs[i]['ytid']}'),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SongBar(
            _songs[i],
            false,
            borderRadius: getItemBorderRadius(i, _songs.length),
            backgroundColor: i == _index || i == _index + 1
                ? Theme.of(context).colorScheme.secondaryContainer
                : null,
            onPlay: () {
              _scaffold.currentState?.closeDrawer();
              unawaited(_select(i));
            },
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                if (edge != null)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (edge.rhythmic)
                        Text(
                          '${edge.bpm.round()} BPM',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      if (edge.camelot != null)
                        Text(
                          edge.camelot!,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                    ],
                  ),
                if (_canReorder)
                  ReorderableDragStartListener(
                    index: i,
                    enabled: !_savingOrder,
                    child: Tooltip(
                      message: context.l10n!.reorderSongs,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
  @override
  Widget build(BuildContext context) {
    final l = context.l10n!;
    final wide = MediaQuery.sizeOf(context).width >= 1050;
    return Scaffold(
      key: _scaffold,
      appBar: AppBar(
        leading: const BackButton(),
        title: Text('Mix · ${_playlist?['title'] ?? l.mixEditTransition}'),
        actions: [
          if (!wide)
            IconButton(
              tooltip: l.mixTracks,
              onPressed: () => _scaffold.currentState?.openDrawer(),
              icon: const Icon(Icons.queue_music),
            ),
          PopupMenuButton<VoidCallback>(
            onSelected: (run) => run(),
            itemBuilder: (_) => [
              PopupMenuItem(value: _analyze, child: Text(l.mixAnalyze)),
              PopupMenuItem(
                enabled: !_analyzing && _canReorder && !_savingOrder,
                value: _smartOrder,
                child: Text(l.mixSmartOrder),
              ),
            ],
          ),
        ],
      ),
      drawer: wide ? null : Drawer(child: SafeArea(child: _tracks())),
      body: Column(
        children: [
          if (_analyzing || _orderChanged || _done > 0 || _savingOrder)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                spacing: 8,
                children: [
                  Expanded(
                    child: Text(
                      _analyzing
                          ? '${l.mixAnalyze} · $_done/${_songs.length}'
                          : _orderChanged
                          ? l.mixOrderPreview
                          : '${l.mixAnalyzed}: $_done · ${l.mixAnalysisFailedCount}: $_failed',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (_analyzing)
                    TextButton(
                      onPressed: _analyze,
                      child: Text(l.mixAnalyzeStop),
                    )
                  else if (_orderChanged)
                    FilledButton.tonal(
                      onPressed: _savingOrder ? null : _saveOrder,
                      child: Text(l.mixApplyOrder),
                    ),
                ],
              ),
            ),
          if (_analyzing) LinearProgressIndicator(value: _done / _songs.length),
          if (_error != null) Text(_error!),
          Expanded(
            child: Row(
              children: [
                if (wide) SizedBox(width: 340, child: _tracks()),
                if (wide) const VerticalDivider(width: 1),
                Expanded(
                  child: MixEditor(
                    key: ValueKey(
                      '${_songs[_index]['ytid']}>${_songs[_index + 1]['ytid']}',
                    ),
                    playlist: widget.playlist,
                    song: _songs[_index],
                    next: _songs[_index + 1],
                    onPrevious: _index > 0 ? () => _select(_index - 1) : null,
                    onNext: _index < _songs.length - 2
                        ? () => _select(_index + 1)
                        : null,
                    pairLabel: '${_index + 1} / ${_songs.length - 1}',
                    stayOnSave: true,
                    hasDraft: _drafts.containsKey(
                      '${_songs[_index]['ytid']}>${_songs[_index + 1]['ytid']}',
                    ),
                    draft:
                        _drafts['${_songs[_index]['ytid']}>${_songs[_index + 1]['ytid']}'],
                    onDraft: (edit) =>
                        _drafts['${_songs[_index]['ytid']}>${_songs[_index + 1]['ytid']}'] =
                            edit,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
