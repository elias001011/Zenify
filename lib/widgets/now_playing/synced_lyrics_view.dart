/*
 *     Copyright (C) 2026 Valeri Gokadze
 *
 *     Musify is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     Musify is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 *
 *     For more information about Musify, including how to contribute,
 *     please visit: https://github.com/gokadzev/Musify
 */

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart';
import 'package:musify/models/position_data.dart';
import 'package:musify/services/lyrics/lyrics_models.dart';
import 'package:musify/widgets/now_playing/lyric_line_fill.dart';

/// Shows time-synced lyrics: the current line is highlighted and kept in view,
/// tapping a line seeks to it, and the timing can be nudged with +/- buttons
/// when a lyrics file is slightly early or late.
class SyncedLyricsView extends StatefulWidget {
  const SyncedLyricsView({super.key, required this.lyrics});

  final Lyrics lyrics;

  @override
  State<SyncedLyricsView> createState() => _SyncedLyricsViewState();
}

class _SyncedLyricsViewState extends State<SyncedLyricsView> {
  static const Duration _offsetStep = Duration(milliseconds: 500);
  static const Duration _manualScrollPause = Duration(seconds: 4);
  static const Duration _scrollDuration = Duration(milliseconds: 650);

  StreamSubscription<PositionData>? _positionSubscription;
  List<GlobalKey> _lineKeys = const [];
  final _progress = ValueNotifier<double>(0);
  Duration _position = Duration.zero;
  Duration _offset = Duration.zero;
  int _activeIndex = -1;
  Size? _viewportSize;
  DateTime _autoScrollResumesAt = DateTime.fromMillisecondsSinceEpoch(0);

  List<LyricLine> get _lines => widget.lyrics.synced ?? const <LyricLine>[];

  @override
  void initState() {
    super.initState();
    _prepareLines();
    _position = audioHandler.currentPositionData.position;
    _activeIndex = _computeActiveIndex();
    _updateProgress();
    _scheduleScrollToActive(animate: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TickerMode.valuesOf(context).enabled) {
      _position = audioHandler.currentPositionData.position;
      _refreshActiveLine();
      _updateProgress();
      _positionSubscription ??= audioHandler.positionDataStream.listen((data) {
        _position = data.position;
        _refreshActiveLine();
        _updateProgress();
      });
    } else {
      unawaited(_positionSubscription?.cancel());
      _positionSubscription = null;
    }
  }

  @override
  void didUpdateWidget(SyncedLyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.lyrics, widget.lyrics)) {
      _prepareLines();
      _offset = Duration.zero;
      _activeIndex = _computeActiveIndex();
      _updateProgress();
      _scheduleScrollToActive(animate: false);
    }
  }

  @override
  void dispose() {
    unawaited(_positionSubscription?.cancel());
    _progress.dispose();
    super.dispose();
  }

  void _updateProgress() {
    if (_activeIndex < 0 || _activeIndex >= _lines.length) return;
    final start = _lines[_activeIndex].start;
    final end = _activeIndex + 1 < _lines.length
        ? _lines[_activeIndex + 1].start
        : audioHandler.currentPositionData.duration;
    final span = (end - start).inMilliseconds;
    _progress.value = span <= 0
        ? 1
        : ((_position + _offset - start).inMilliseconds / span).clamp(0.0, 1.0);
  }

  void _prepareLines() {
    _lineKeys = List<GlobalKey>.generate(_lines.length, (_) => GlobalKey());
  }

  int _computeActiveIndex() => widget.lyrics.lineIndexAt(_position + _offset);

  void _refreshActiveLine() {
    final index = _computeActiveIndex();
    if (index == _activeIndex || !mounted) return;
    setState(() => _activeIndex = index);
    _scheduleScrollToActive();
  }

  void _scheduleScrollToActive({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (DateTime.now().isBefore(_autoScrollResumesAt)) return;
      if (_activeIndex < 0 || _activeIndex >= _lineKeys.length) return;

      final lineContext = _lineKeys[_activeIndex].currentContext;
      if (lineContext == null) return;

      unawaited(
        Scrollable.ensureVisible(
          lineContext,
          alignment: 0.4,
          duration: !animate || MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : _scrollDuration,
          curve: Curves.easeInOutCubic,
        ),
      );
    });
  }

  void _changeOffset(Duration delta) {
    setState(() {
      _offset = delta == Duration.zero ? Duration.zero : _offset + delta;
      _activeIndex = _computeActiveIndex();
    });
    _updateProgress();
    _autoScrollResumesAt = DateTime.fromMillisecondsSinceEpoch(0);
    _scheduleScrollToActive();
  }

  void _seekToLine(LyricLine line) {
    final target = line.start - _offset;
    unawaited(audioHandler.seek(target.isNegative ? Duration.zero : target));
    _autoScrollResumesAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  String get _offsetLabel {
    if (_offset == Duration.zero) return '0.0s';
    final seconds = _offset.inMilliseconds / 1000;
    return '${seconds > 0 ? '+' : ''}${seconds.toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textColor = colorScheme.onSurface;
    final lines = _lines;

    return Column(
      children: [
        Expanded(
          child: NotificationListener<ScrollStartNotification>(
            onNotification: (notification) {
              // Only a finger/mouse drag pauses auto-scroll, not our own
              // ensureVisible animation (which has no drag details).
              if (notification.dragDetails != null) {
                _autoScrollResumesAt = DateTime.now().add(_manualScrollPause);
              }
              return false;
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Resizing reflows the lines and changes the edge padding.
                // A pixel offset alone no longer keeps the current verse in
                // view, even when playback is paused and emits no new ticks.
                if (_viewportSize != constraints.biggest) {
                  _viewportSize = constraints.biggest;
                  _scheduleScrollToActive(animate: false);
                }
                // Blank space above and below lets the first and last lines
                // reach the vertical middle of the card.
                final edgePadding = constraints.maxHeight * 0.4;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    edgePadding,
                    20,
                    edgePadding,
                  ),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < lines.length; i++)
                        _buildLine(
                          i,
                          lines[i],
                          textColor,
                          constraints.maxWidth >= 500 ? 32 : 20,
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Text(
                          '© ${widget.lyrics.source}',
                          style: TextStyle(
                            fontSize: 12,
                            color: textColor.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        _buildOffsetControls(textColor),
      ],
    );
  }

  Widget _buildLine(
    int index,
    LyricLine line,
    Color baseColor,
    double fontSize,
  ) {
    final isActive = index == _activeIndex;
    final spacious = fontSize >= 28;
    final align = spacious ? TextAlign.start : TextAlign.center;
    final style = TextStyle(
      fontSize: fontSize,
      height: spacious ? 1.35 : 1.4,
      fontWeight: spacious ? FontWeight.w700 : FontWeight.w800,
      color: baseColor,
    );
    return GestureDetector(
      key: _lineKeys[index],
      behavior: HitTestBehavior.opaque,
      onTap: () => _seekToLine(line),
      child: TweenAnimationBuilder<double>(
        tween: Tween(
          end: MediaQuery.disableAnimationsOf(context) || isActive ? 1.0 : 0.0,
        ),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        builder: (context, amount, child) => Transform.translate(
          offset: Offset(0, 3 * (1 - amount)),
          child: Transform.scale(
            scaleX: 1,
            scaleY: 0.98 + 0.02 * amount,
            alignment: Alignment.bottomCenter,
            child: child,
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: spacious ? 18 : 6),
          child: ValueListenableBuilder<double>(
            valueListenable: isActive
                ? _progress
                : AlwaysStoppedAnimation<double>(index < _activeIndex ? 1 : 0),
            builder: (context, progress, _) => LyricLineFill(
              text: line.text.isEmpty ? '♪' : line.text,
              style: style,
              textAlign: align,
              progress: progress,
              emphasis: isActive ? 1 : 0,
              baseOpacity: isActive
                  ? 0.38
                  : index < _activeIndex
                  ? 0.28
                  : 0.45,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 300),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOffsetControls(Color color) {
    final dimmed = color.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            color: dimmed,
            icon: const Icon(FluentIcons.subtract_24_regular),
            onPressed: () => _changeOffset(-_offsetStep),
          ),
          GestureDetector(
            onTap: () => _changeOffset(Duration.zero),
            child: Text(
              _offsetLabel,
              style: TextStyle(fontSize: 12, color: dimmed),
            ),
          ),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            color: dimmed,
            icon: const Icon(FluentIcons.add_24_regular),
            onPressed: () => _changeOffset(_offsetStep),
          ),
        ],
      ),
    );
  }
}
