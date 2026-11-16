import 'dart:async';
import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/mix_page.dart';
import 'package:musify/services/mix_analysis.dart';
import 'package:musify/services/mix_edits.dart';
import 'package:musify/services/mix_harmony.dart';
import 'package:musify/services/mix_transition.dart';
import 'package:musify/utilities/media_duration.dart';
import 'package:musify/utilities/platform_utils.dart';
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

/// The transition of two songs on their own, as the queue plays them.
Future<void> showPairEditor(
  BuildContext context,
  String playlist,
  Map song,
  Map next,
) => Navigator.of(context, rootNavigator: true).push<void>(
  MaterialPageRoute(
    builder: (_) => Scaffold(
      appBar: AppBar(),
      body: MixEditor(playlist: playlist, song: song, next: next),
    ),
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
  // Songs saved without a duration get it from their analysis.
  late Duration? _duration = readMediaDuration(widget.song['duration']);
  late Duration? _coming = readMediaDuration(widget.next['duration']);
  late MixCue _cue;
  bool _automatic = true;
  bool _loading = true;
  bool _previewing = false;
  bool _saving = false;
  String? _error;
  MixInspection? _tail;
  MixInspection? _head;
  // The stretches SponsorBlock skips: the transition keeps out of them.
  List<MixSkip> _outSkips = const [];
  List<MixSkip> _inSkips = const [];
  Timer? _clock;
  double? _playhead;
  int _audition = 0;
  late final MixEdit? _initialEdit;

  bool get _canEdit =>
      _duration != null &&
      _coming != null &&
      _duration! >= const Duration(seconds: 1) &&
      _coming! >= const Duration(seconds: 1);
  bool get _busy => _previewing || _saving;

  @override
  void initState() {
    super.initState();
    final edit = _initialEdit = widget.hasDraft
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
    echo: isDesktopPlatform,
    endAt: mixBounds(_outSkips, _duration).end,
    startAt: mixBounds(_inSkips, _coming).start,
  );

  Future<void> _load() async {
    final skips = Future.wait([
      audioHandler.mixSkips(widget.song),
      audioHandler.mixSkips(widget.next),
    ]).catchError((Object _) => const [<MixSkip>[], <MixSkip>[]]);
    final edges = await Future.wait([
      _analyzer.inspect(widget.song, tail: true, duration: _duration),
      _analyzer.inspect(widget.next, tail: false, duration: _coming),
    ]);
    final skipped = await skips;
    if (!mounted) return;
    setState(() {
      _outSkips = skipped[0];
      _inSkips = skipped[1];
      _tail = edges[0];
      _head = edges[1];
      _loading = false;
      final known = _canEdit;
      if (_tail case final tail?) {
        _duration ??= Duration(milliseconds: tail.offset + tail.length);
      }
      if (_head case final head?) {
        _coming ??= Duration(milliseconds: head.offset + head.length);
      }
      if (_previewing) return;
      if (_automatic) {
        _cue = _autoCue();
      } else if (!known && _canEdit) {
        // A saved edit is bound to the songs only once both lengths are known.
        _cue = (_initialEdit ?? MixEdit.fromCue(_cue)).cue(_duration!, _coming);
      }
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
    final total = min(
      _duration!.inMilliseconds,
      mixBounds(_outSkips, _duration).end ?? _duration!.inMilliseconds,
    );
    final coming = _coming!.inMilliseconds;
    final opening = mixBounds(_inSkips, _coming).start;
    var outMs = out == null
        ? _cue.outStart.inMilliseconds
        : (out * 1000).round();
    final inMs = max(
      opening,
      into == null ? _cue.inStart.inMilliseconds : (into * 1000).round(),
    );
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
            mixLongestTransition.inMilliseconds,
            min(end, ((coming - inMs) / (ratio ?? _cue.tempoRatio)).floor()),
          ),
        ),
      );
      outMs = end - nextLength;
    } else if (length != null) {
      // An edge of the window was dragged: the rest of both songs bounds it.
      outMs = outMs.clamp(0, max(0, total - 500));
      nextLength = nextLength.clamp(
        500,
        max(
          500,
          min(
            mixLongestTransition.inMilliseconds,
            min(
              total - outMs,
              ((coming - inMs) / (ratio ?? _cue.tempoRatio)).floor(),
            ),
          ),
        ),
      );
    }
    setState(() {
      _automatic = false;
      _cue = MixEdit(
        outStart: Duration(milliseconds: outMs.clamp(0, max(0, total - 500))),
        inStart: Duration(milliseconds: inMs.clamp(0, max(0, coming - 500))),
        length: Duration(milliseconds: nextLength),
        style: style ?? _cue.style,
        volume: style != null ? null : volume ?? _cue.volume,
        eq: style != null ? null : eq ?? _cue.eq,
        filter: style != null ? null : filter ?? _cue.filter,
        tempoRatio: ratio ?? _cue.tempoRatio,
      ).cue(_duration!, _coming);
      widget.onDraft?.call(MixEdit.fromCue(_cue));
    });
  }

  // Where a drag has taken the song, before it is put on a bar.
  double? _dragOut, _dragIn;

  /// The bar line of [inspection]'s song nearest to [ms], at or after [from];
  /// [ms] itself when the song has no beat.
  int _onBar(MixInspection? inspection, double ms, {int from = 0}) {
    final edge = inspection?.edge;
    if (edge == null || !edge.rhythmic) return ms.round();
    final beat = 60000 / edge.bpm;
    final origin = edge.beatAt + edge.bar * beat;
    var at = origin + ((ms - origin) / (4 * beat)).round() * 4 * beat;
    while (at < from) {
      at += 4 * beat;
    }
    return at.round();
  }

  void _dragOutgoing(double delta) {
    final total = _duration!.inMilliseconds.toDouble();
    final raw =
        ((_dragOut ?? _cue.outStart.inMilliseconds.toDouble()) + delta * 1000)
            .clamp(0.0, total);
    _dragOut = raw;
    _change(out: _onBar(_tail, raw) / 1000);
  }

  void _dragIncoming(double delta) {
    final total = _coming!.inMilliseconds.toDouble();
    final raw =
        ((_dragIn ?? _cue.inStart.inMilliseconds.toDouble()) +
                delta * 1000 * _cue.tempoRatio)
            .clamp(0.0, total);
    _dragIn = raw;
    _change(
      into: _onBar(_head, raw, from: mixBounds(_inSkips, _coming).start) / 1000,
    );
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

  /// The length of the transition, in bars when the song has a beat.
  String _lengthLabel(String bars) {
    final seconds = _cue.length.inMilliseconds / 1000;
    final edge = _tail?.edge;
    if (edge == null || !edge.rhythmic)
      return '${seconds.toStringAsFixed(1)} s';
    final count = seconds * edge.bpm / 240;
    final round = (count - count.round()).abs() < 0.06;
    return '${round ? count.round() : count.toStringAsFixed(1)} $bars';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rhythmic = _tail?.edge.rhythmic == true;
    Widget song(Map data, MixInspection? inspection, bool incoming) => SongBar(
      data,
      false,
      borderRadius: commonCustomBarRadius,
      onPlay: _canEdit ? () => _preview(at: incoming ? 0 : -5) : () {},
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: 4,
        children: [
          if (inspection?.edge.rhythmic == true)
            Text(
              '${inspection!.edge.bpm.round()} BPM',
              style: theme.textTheme.labelMedium,
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 6,
            children: [
              if (inspection?.edge.camelot != null)
                Tooltip(
                  message: l.mixKeyEstimated,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: incoming
                          ? colors.tertiaryContainer
                          : colors.primaryContainer,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      inspection!.edge.camelot!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: incoming
                            ? colors.onTertiaryContainer
                            : colors.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              Text(
                _time((incoming ? _coming : _duration) ?? Duration.zero),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final lengths = <(String, double)>[
      if (rhythmic)
        for (final bars in [1, 2, 4, 8, 16, 32])
          if (bars * 240 / _tail!.edge.bpm <= mixLongestTransition.inSeconds)
            ('$bars ${l.mixBars}', bars * 240 / _tail!.edge.bpm),
      if (!rhythmic)
        for (final seconds in [2, 4, 8, 12, 16]) ('$seconds s', seconds * 1.0),
    ];
    final status = !_canEdit
        ? l.mixDurationUnavailable
        : !_loading && (_tail == null || _head == null)
        ? l.mixAnalysisUnavailable
        : l.mixSeekHint;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.mixEditTransition,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    if (widget.pairLabel != null) ...[
                      IconButton(
                        tooltip: l.mixPreviousPair,
                        onPressed: widget.onPrevious,
                        icon: const Icon(FluentIcons.chevron_left_24_regular),
                      ),
                      Text(widget.pairLabel!),
                      IconButton(
                        tooltip: l.mixNextPair,
                        onPressed: widget.onNext,
                        icon: const Icon(FluentIcons.chevron_right_24_regular),
                      ),
                    ] else
                      const SizedBox(height: 40),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: song(widget.song, _tail, false),
                      ),
                      const SizedBox(height: 6),
                      MixTimeline(
                        cue: _cue,
                        tail: _tail,
                        head: _head,
                        outSkips: _outSkips,
                        inSkips: _inSkips,
                        playhead: _playhead,
                        outLabel: _canEdit ? _time(_cue.outStart) : null,
                        inLabel: _canEdit ? _time(_cue.inStart) : null,
                        onSeek: _canEdit && !_saving
                            ? (at) => _preview(at: at)
                            : null,
                        onDragEnd: () => _dragOut = _dragIn = null,
                        onOutgoing: _canEdit && !_busy ? _dragOutgoing : null,
                        onIncoming: _canEdit && !_busy ? _dragIncoming : null,
                        onResize: _canEdit && !_busy
                            ? (start, length) => _change(
                                out:
                                    _cue.outStart.inMilliseconds / 1000 + start,
                                length:
                                    _cue.length.inMilliseconds / 1000 + length,
                              )
                            : null,
                        play: IconButton.filled(
                          tooltip: _previewing
                              ? l.mixStopPreview
                              : l.mixPreview,
                          onPressed: _canEdit && !_saving ? _preview : null,
                          style: IconButton.styleFrom(
                            backgroundColor: colors.inverseSurface,
                            foregroundColor: colors.onInverseSurface,
                            fixedSize: const Size(56, 40),
                          ),
                          icon: Icon(
                            _previewing
                                ? FluentIcons.stop_24_filled
                                : FluentIcons.play_24_filled,
                            size: 20,
                          ),
                        ),
                        length: !_canEdit
                            ? null
                            : PopupMenuButton<double>(
                                enabled: !_busy,
                                tooltip: l.mixLength,
                                position: PopupMenuPosition.under,
                                onSelected: (v) => _change(length: v),
                                itemBuilder: (_) => [
                                  for (final (label, seconds) in lengths)
                                    PopupMenuItem(
                                      value: seconds,
                                      child: Text(label),
                                    ),
                                ],
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    5,
                                    8,
                                    5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: colors.outlineVariant,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    spacing: 4,
                                    children: [
                                      Text(
                                        _lengthLabel(l.mixBars),
                                        style: theme.textTheme.labelMedium,
                                      ),
                                      const Icon(
                                        FluentIcons.chevron_down_16_regular,
                                        size: 14,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ),
                      SizedBox(
                        height: 3,
                        child: _loading
                            ? const LinearProgressIndicator(minHeight: 3)
                            : null,
                      ),
                      const SizedBox(height: 3),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: song(widget.next, _head, true),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                        child: Text(
                          _error ?? status,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _error != null
                                ? colors.error
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (_canEdit)
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: colors.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            children: [
                              _options<MixVolume>(
                                l.mixVolumeCurve,
                                colors.primary,
                                _cue.volume ?? _cue.style.volume,
                                {
                                  MixVolume.crossfade: 'Crossfade',
                                  MixVolume.overlap: l.mixOverlap,
                                  MixVolume.fadeOutIn: l.mixSequentialFade,
                                  MixVolume.riseUnder: l.mixRiseUnder,
                                  MixVolume.centerCut: l.mixCut,
                                  MixVolume.cutIn: l.mixCutIn,
                                },
                                (v) => _change(volume: v),
                              ),
                              _options<MixEq>(
                                l.mixEqCurve,
                                colors.secondary,
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
                                colors.tertiary,
                                _cue.filter ?? _cue.style.filter,
                                {
                                  MixFilter.none: l.mixNone,
                                  MixFilter.highPassOut: l.mixHighPass,
                                  MixFilter.lowPassIn: l.mixLowPass,
                                  MixFilter.both: l.mixBothFilters,
                                  if (isDesktopPlatform)
                                    MixFilter.echoOut: l.mixEchoOut,
                                },
                                (v) => _change(filter: v),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              avatar: Icon(
                                FluentIcons.sparkle_20_regular,
                                size: 18,
                                color: _automatic
                                    ? colors.onSecondaryContainer
                                    : colors.onSurfaceVariant,
                              ),
                              showCheckmark: false,
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
                              ChoiceChip(
                                showCheckmark: false,
                                label: Text(l.mixCustom),
                                selected: true,
                              ),
                            for (final style in MixStyle.values)
                              if (style != MixStyle.echo || isDesktopPlatform)
                                ChoiceChip(
                                  showCheckmark: false,
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
                            if (rhythmic &&
                                _head?.edge.rhythmic == true &&
                                tempoGap(_tail!.edge.bpm, _head!.edge.bpm) <=
                                    0.06 &&
                                tempoGap(_tail!.edge.bpm, _head!.edge.bpm) >
                                    0.001)
                              FilterChip(
                                label: Text(l.mixTempoSync),
                                selected: _cue.tempoRatio != 1,
                                onSelected: _busy
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
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _canEdit && !_busy ? _save : null,
                    child: Text(l.mixSave),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One of the three things a transition is made of, with its menu.
  Widget _options<T>(
    String label,
    Color color,
    T value,
    Map<T, String> options,
    ValueChanged<T> change,
  ) {
    final theme = Theme.of(context);
    return Expanded(
      child: PopupMenuButton<T>(
        enabled: !_busy,
        tooltip: label,
        initialValue: value,
        onSelected: change,
        itemBuilder: (_) => [
          for (final entry in options.entries)
            PopupMenuItem(value: entry.key, child: Text(entry.value)),
        ],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Column(
            spacing: 2,
            children: [
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(color: color),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 2,
                children: [
                  Flexible(
                    child: Text(
                      options[value] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const Icon(FluentIcons.chevron_down_16_regular, size: 14),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
