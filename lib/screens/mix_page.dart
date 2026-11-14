import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/mix_edits.dart';
import 'package:musify/services/mix_playlist_analysis.dart';
import 'package:musify/services/playlists_manager.dart';
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
  String? _error;
  final _drafts = <String, MixEdit?>{};
  final _scaffold = GlobalKey<ScaffoldState>();
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
      var failed = duration == null;
      if (duration != null) {
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
    if (_playlist == null) return;
    try {
      // Read again so a title or playlist update made elsewhere is preserved.
      final current = await getPlaylistInfoForWidget(widget.playlist);
      if (current == null) return;
      final currentIds = (current['list'] as List)
          .map((s) => s['ytid'])
          .toList();
      final ids = _songs.map((s) => s['ytid']).toList();
      if (currentIds.length != ids.length || !currentIds.every(ids.contains)) {
        await _load();
        return;
      }
      final latest = {
        for (final song in current['list'] as List) song['ytid']: song,
      };
      final reordered = [for (final id in ids) latest[id]];
      if (!await replaceCustomPlaylist(widget.playlist, {
        ...current,
        'list': reordered,
      }))
        return;
      if (mounted)
        setState(() {
          _orderChanged = false;
          _playlist = {...current, 'list': _songs};
        });
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n!.mixSaveFailed);
    }
  }

  Widget _tracks() => ListenableBuilder(
    listenable: audioHandler.mixAnalyzer.changes,
    builder: (context, _) => ListView.builder(
      itemCount: _songs.length,
      itemBuilder: (context, i) {
        final edge = audioHandler.mixAnalyzer.edge(_songs[i], tail: false);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: SongBar(
            _songs[i],
            false,
            backgroundColor: i == _index || i == _index + 1
                ? Theme.of(context).colorScheme.secondaryContainer
                : null,
            onPlay: () {
              _scaffold.currentState?.closeDrawer();
              unawaited(_select(i));
            },
            trailing: edge == null
                ? null
                : Column(
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
        ],
      ),
      drawer: wide ? null : Drawer(child: SafeArea(child: _tracks())),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _analyze,
                    icon: Icon(_analyzing ? Icons.stop : Icons.graphic_eq),
                    label: Text(
                      _analyzing
                          ? '${l.mixAnalyzeStop} · $_done/${_songs.length}'
                          : l.mixAnalyze,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _analyzing
                        ? null
                        : () async {
                            await audioHandler.stopMixPreview();
                            if (!mounted) return;
                            setState(() {
                              _songs = orderMixSongs(
                                _songs,
                                audioHandler.mixAnalyzer,
                              );
                              _index = 0;
                              _orderChanged = true;
                            });
                          },
                    icon: const Icon(Icons.sort),
                    label: Text(l.mixSmartOrder),
                  ),
                  if (_orderChanged)
                    FilledButton(
                      onPressed: _saveOrder,
                      child: Text(l.mixApplyOrder),
                    ),
                  if (_done > 0 && !_analyzing)
                    Text(
                      '${l.mixAnalyzed}: $_done · ${l.mixAnalysisFailedCount}: $_failed',
                    ),
                ],
              ),
            ),
          ),
          if (_analyzing) LinearProgressIndicator(value: _done / _songs.length),
          if (_orderChanged) Text(l.mixOrderPreview),
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
