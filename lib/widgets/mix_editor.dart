import 'dart:async';
import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/mix_page.dart';
import 'package:musify/services/mix_analysis.dart';
import 'package:musify/services/mix_edits.dart';
import 'package:musify/services/mix_harmony.dart';
import 'package:musify/services/mix_transition.dart';
import 'package:musify/utilities/media_duration.dart';
import 'package:musify/widgets/mix_timeline.dart';
import 'package:musify/widgets/song_bar.dart';

Future<void> showMixEditor(
  BuildContext context,
  String playlist,
  Map song,
  Map next,
) => Navigator.of(context, rootNavigator: true).push<void>(
  MaterialPageRoute(
    builder: (_) => MixPage(playlist: playlist, song: song, next: next),
  ),
);

class MixEditor extends StatefulWidget {
  const MixEditor({
    super.key,
    required this.playlist,
    required this.song,
    required this.next,
    this.analyzer,
    this.onPrevious,
    this.onNext,
    this.pairLabel,
    this.stayOnSave = false,
    this.hasDraft = false,
    this.draft,
    this.onDraft,
  });
  final String playlist;
  final Map song;
  final Map next;
  final MixAnalyzer? analyzer;
  final VoidCallback? onPrevious, onNext;
  final String? pairLabel;
  final bool stayOnSave;
  final bool hasDraft;
  final MixEdit? draft;
  final ValueChanged<MixEdit?>? onDraft;

  @override
  State<MixEditor> createState() => _MixEditorState();
}

class _MixEditorState extends State<MixEditor> {
  late final _analyzer = widget.analyzer ?? audioHandler.mixAnalyzer;
  late final _duration = readMediaDuration(widget.song['duration']);
  late final _coming = readMediaDuration(widget.next['duration']);
  late MixCue _cue;
  bool _automatic = true;
  bool _loading = true;
  bool _previewing = false;
  bool _saving = false;
  String? _error;
  MixInspection? _tail;
  MixInspection? _head;
  Timer? _clock;
  double? _playhead;
  int _audition = 0;

  bool get _canEdit =>
      _duration != null &&
      _coming != null &&
      _duration >= const Duration(seconds: 1) &&
      _coming >= const Duration(seconds: 1);
  bool get _busy => _previewing || _saving;

  @override
  void initState() {
    super.initState();
    final edit = widget.hasDraft
        ? widget.draft
        : mixEdits.get(
            widget.playlist,
            widget.song['ytid']?.toString(),
            widget.next['ytid']?.toString(),
          );
    _automatic = edit == null;
    _cue = edit?.cue(_duration ?? Duration.zero, _coming) ?? _autoCue();
    unawaited(_load());
  }

  MixCue _autoCue() => chooseCue(
    duration: _duration ?? const Duration(seconds: 60),
    coming: _coming,
    tail: _tail?.edge ?? _analyzer.edge(widget.song, tail: true),
    head: _head?.edge ?? _analyzer.edge(widget.next, tail: false),
    pair: '${widget.song['ytid']}>${widget.next['ytid']}',
  );

  Future<void> _load() async {
    if (!_canEdit) {
      setState(() => _loading = false);
      return;
    }
    final edges = await Future.wait([
      _analyzer.inspect(widget.song, tail: true, duration: _duration!),
      _analyzer.inspect(widget.next, tail: false, duration: _coming!),
    ]);
    if (!mounted) return;
    setState(() {
      _tail = edges[0];
      _head = edges[1];
      _loading = false;
      if (_automatic && !_previewing) _cue = _autoCue();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _audition++;
    if (_previewing) unawaited(audioHandler.stopMixPreview());
    super.dispose();
  }

  String _time(Duration value) {
    final seconds = value.inMilliseconds / 1000;
    return '${seconds ~/ 60}:${(seconds % 60).toStringAsFixed(1).padLeft(4, '0')}';
  }

  void _change({
    double? out,
    double? into,
    double? length,
    MixStyle? style,
    MixVolume? volume,
    MixEq? eq,
    MixFilter? filter,
    double? ratio,
  }) {
    final total = _duration!.inMilliseconds;
    final coming = _coming!.inMilliseconds;
    var outMs = out == null
        ? _cue.outStart.inMilliseconds
        : (out * 1000).round();
    final inMs = into == null
        ? _cue.inStart.inMilliseconds
        : (into * 1000).round();
    var nextLength = length == null
        ? _cue.length.inMilliseconds
        : (length * 1000).round();
    if (length != null && out == null) {
      // Length presets extend backwards from the existing exit marker, so
      // choosing eight bars actually grows a transition near the track end.
      final end = min(total, (_cue.outStart + _cue.length).inMilliseconds);
      nextLength = nextLength.clamp(
        1,
        max(
          1,
          min(
            40000,
            min(
              end - max(0, total - 40000),
              ((coming - inMs) / (ratio ?? _cue.tempoRatio)).floor(),
            ),
          ),
        ),
      );
      outMs = end - nextLength;
    }
    setState(() {
      _automatic = false;
      _cue = MixEdit(
        outStart: Duration(
          milliseconds: outMs.clamp(max(0, total - 40000), total - 500),
        ),
        inStart: Duration(
          milliseconds: inMs.clamp(0, min(40000, coming - 500)),
        ),
        length: Duration(milliseconds: nextLength),
        style: style ?? _cue.style,
        volume: style != null ? null : volume ?? _cue.volume,
        eq: style != null ? null : eq ?? _cue.eq,
        filter: style != null ? null : filter ?? _cue.filter,
        tempoRatio: ratio ?? _cue.tempoRatio,
      ).cue(_duration, _coming);
      widget.onDraft?.call(MixEdit.fromCue(_cue));
    });
  }

  Future<void> _preview({double? at}) async {
    if (_previewing && at == null) {
      await audioHandler.stopMixPreview();
      return;
    }
    final request = ++_audition;
    if (_previewing) await audioHandler.stopMixPreview();
    if (!mounted || request != _audition) return;
    setState(() {
      _previewing = true;
      _error = null;
    });
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!mounted || !_previewing) return;
      final incoming =
          audioHandler.mediaItem.valueOrNull?.extras?['ytid'] ==
          widget.next['ytid'];
      final position = audioHandler.audioPlayer.position;
      setState(
        () => _playhead = incoming
            ? (position - _cue.inStart).inMilliseconds / 1000 / _cue.tempoRatio
            : (position - _cue.outStart).inMilliseconds / 1000,
      );
    });
    final success = await audioHandler.previewMix(
      widget.song,
      widget.next,
      _cue,
      startAt: at == null
          ? null
          : Duration(
              milliseconds: max(
                0,
                _cue.outStart.inMilliseconds + (at * 1000).round(),
              ),
            ),
    );
    if (!mounted || request != _audition) return;
    _clock?.cancel();
    setState(() {
      _previewing = false;
      _playhead = null;
      if (!success) _error = context.l10n!.mixPreviewFailed;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await audioHandler.stopMixPreview();
      await mixEdits.set(
        widget.playlist,
        widget.song['ytid'].toString(),
        widget.next['ytid'].toString(),
        _automatic ? null : MixEdit.fromCue(_cue),
      );
      audioHandler.refreshMix();
      if (mounted) {
        if (widget.stayOnSave) {
          setState(() => _saving = false);
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(context.l10n!.mixSave)));
        } else {
          Navigator.of(context).pop();
        }
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = context.l10n!.mixSaveFailed;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Widget song(Map data, MixInspection? inspection, bool incoming) => SongBar(
      data,
      false,
      onPlay: _canEdit ? () => _preview(at: incoming ? 0 : -5) : () {},
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (inspection?.edge.rhythmic == true)
            Text(
              '${inspection!.edge.bpm.round()} BPM',
              style: theme.textTheme.labelMedium,
            ),
          if (inspection?.edge.camelot != null)
            Tooltip(
              message: l.mixKeyEstimated,
              child: Text(
                inspection!.edge.camelot!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.primary,
                ),
              ),
            ),
          Text(
            _time(readMediaDuration(data['duration']) ?? Duration.zero),
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l.mixEditTransition,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                if (widget.pairLabel != null) ...[
                  IconButton(
                    tooltip: l.mixPreviousPair,
                    onPressed: widget.onPrevious,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(widget.pairLabel!),
                  IconButton(
                    tooltip: l.mixNextPair,
                    onPressed: widget.onNext,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  song(widget.song, _tail, false),
                  const SizedBox(height: 12),
                  if (_loading) const LinearProgressIndicator(),
                  MixTimeline(
                    cue: _cue,
                    tail: _tail,
                    head: _head,
                    playhead: _playhead,
                    onSeek: _canEdit && !_saving
                        ? (at) => _preview(at: at)
                        : null,
                    onOutgoing: _canEdit && !_busy
                        ? (delta) => _change(
                            out: _cue.outStart.inMilliseconds / 1000 + delta,
                          )
                        : null,
                    onIncoming: _canEdit && !_busy
                        ? (delta) => _change(
                            into:
                                _cue.inStart.inMilliseconds / 1000 +
                                delta * _cue.tempoRatio,
                          )
                        : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _time(_cue.outStart),
                          style: theme.textTheme.labelSmall,
                        ),
                        Text(
                          '${(_cue.length.inMilliseconds / 1000).toStringAsFixed(1)} s',
                          style: theme.textTheme.labelMedium,
                        ),
                        Text(
                          _time(_cue.inStart),
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  song(widget.next, _head, true),
                  const SizedBox(height: 8),
                  Text(
                    !_canEdit
                        ? l.mixDurationUnavailable
                        : !_loading && (_tail == null || _head == null)
                        ? l.mixAnalysisUnavailable
                        : l.mixSeekHint,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(l.mixAutomatic),
                          selected: _automatic,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() {
                                  widget.onDraft?.call(null);
                                  _automatic = true;
                                  _cue = _autoCue();
                                }),
                        ),
                        if (!_automatic && _cue.customized)
                          ChoiceChip(label: Text(l.mixCustom), selected: true),
                        for (final style in MixStyle.values)
                          ChoiceChip(
                            label: Text(switch (style) {
                              MixStyle.smooth => 'Crossfade',
                              MixStyle.fadeOut => l.mixSequentialFade,
                              MixStyle.slam => l.mixCut,
                              _ =>
                                style.name[0].toUpperCase() +
                                    style.name.substring(1),
                            }),
                            selected:
                                !_automatic &&
                                !_cue.customized &&
                                _cue.style == style,
                            onSelected: _canEdit && !_busy
                                ? (_) => _change(style: style)
                                : null,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(l.mixAutoReason, style: theme.textTheme.bodySmall),
                  if (_canEdit) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 12,
                      children: [
                        _options<MixVolume>(
                          l.mixVolumeCurve,
                          _cue.volume ?? _cue.style.volume,
                          {
                            MixVolume.crossfade: 'Crossfade',
                            MixVolume.overlap: l.mixOverlap,
                            MixVolume.fadeOutIn: l.mixSequentialFade,
                            MixVolume.riseUnder: l.mixRiseUnder,
                            MixVolume.centerCut: l.mixCut,
                          },
                          (v) => _change(volume: v),
                        ),
                        _options<MixEq>(
                          l.mixEqCurve,
                          _cue.eq ?? _cue.style.eq,
                          {
                            MixEq.none: l.mixNone,
                            MixEq.bassSwapCenter: l.mixBassCenter,
                            MixEq.bassSwapEnd: l.mixBassEnd,
                            MixEq.threeBand: l.mixThreeBand,
                          },
                          (v) => _change(eq: v),
                        ),
                        _options<MixFilter>(
                          l.mixEffect,
                          _cue.filter ?? _cue.style.filter,
                          {
                            MixFilter.none: l.mixNone,
                            MixFilter.highPassOut: l.mixHighPass,
                            MixFilter.lowPassIn: l.mixLowPass,
                            MixFilter.both: l.mixBothFilters,
                          },
                          (v) => _change(filter: v),
                        ),
                      ],
                    ),
                    if (_tail?.edge.rhythmic == true) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final bars in [2, 4, 8])
                            ActionChip(
                              label: Text('$bars ${l.mixBars}'),
                              onPressed: _busy
                                  ? null
                                  : () => _change(
                                      length: bars * 4 * 60 / _tail!.edge.bpm,
                                    ),
                            ),
                        ],
                      ),
                    ],
                    if (_tail?.edge.rhythmic == true &&
                        _head?.edge.rhythmic == true &&
                        tempoGap(_tail!.edge.bpm, _head!.edge.bpm) <= 0.06 &&
                        tempoGap(_tail!.edge.bpm, _head!.edge.bpm) > 0.001)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l.mixTempoSync),
                        subtitle: Text(
                          '${_tail!.edge.bpm.round()} / ${_head!.edge.bpm.round()} BPM',
                        ),
                        value: _cue.tempoRatio != 1,
                        onChanged: _busy
                            ? null
                            : (v) => _change(
                                ratio: v
                                    ? tempoRatio(
                                        _tail!.edge.bpm,
                                        _head!.edge.bpm,
                                      )
                                    : 1,
                              ),
                      ),
                    const SizedBox(height: 20),
                    _slider(
                      l.mixOutPoint,
                      _cue.outStart.inMilliseconds / 1000,
                      max(0, _duration!.inMilliseconds / 1000 - 40),
                      _duration.inMilliseconds / 1000 - 0.5,
                      (v) => _change(out: v),
                      time: true,
                    ),
                    _slider(
                      l.mixInPoint,
                      _cue.inStart.inMilliseconds / 1000,
                      0,
                      min(40, _coming!.inMilliseconds / 1000 - 0.5),
                      (v) => _change(into: v),
                      time: true,
                    ),
                    _slider(
                      l.mixLength,
                      _cue.length.inMilliseconds / 1000,
                      0.5,
                      min(
                        40,
                        min(
                              min(
                                    _duration.inMilliseconds,
                                    (_cue.outStart + _cue.length)
                                        .inMilliseconds,
                                  ) -
                                  max(0, _duration.inMilliseconds - 40000),
                              ((_coming - _cue.inStart).inMilliseconds /
                                      _cue.tempoRatio)
                                  .floor(),
                            ) /
                            1000,
                      ),
                      (v) => _change(length: v),
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _canEdit && !_saving ? _preview : null,
                  icon: Icon(
                    _previewing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
                  label: Text(_previewing ? l.mixStopPreview : l.mixPreview),
                ),
                FilledButton.icon(
                  onPressed: _canEdit && !_busy ? _save : null,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(l.mixSave),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _options<T>(
    String label,
    T value,
    Map<T, String> options,
    ValueChanged<T> change,
  ) => SizedBox(
    width: 220,
    child: DropdownButtonFormField<T>(
      initialValue: value,
      key: ValueKey('$label:$value'),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      isExpanded: true,
      items: [
        for (final entry in options.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(entry.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: _busy
          ? null
          : (v) {
              if (v != null) change(v);
            },
    ),
  );

  Widget _slider(
    String label,
    double value,
    double minValue,
    double maxValue,
    ValueChanged<double> change, {
    bool time = false,
  }) {
    maxValue = max(minValue, maxValue);
    final shown = time
        ? _time(Duration(milliseconds: (value * 1000).round()))
        : '${value.toStringAsFixed(1)} s';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('$label · $shown'),
        Slider(
          value: value.clamp(minValue, maxValue),
          min: minValue,
          max: maxValue,
          label: shown,
          onChanged: _busy || maxValue == minValue ? null : change,
        ),
      ],
    );
  }
}
