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

import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart';
import 'package:musify/models/position_data.dart';
import 'package:musify/utilities/formatter.dart';
import 'package:musify/widgets/now_playing/audio_quality_badge.dart';
import 'package:musify/widgets/now_playing/player_chrome.dart';

class PositionSlider extends StatefulWidget {
  /// The track and the times reach the edges of the space they are given, so
  /// the player's buttons and the artwork can line up with them.
  const PositionSlider({super.key, this.inline = false});

  /// A short bar with the times on its two sides, on one line, for the desktop
  /// mini player; by default the times are under the bar.
  final bool inline;

  @override
  State<PositionSlider> createState() => _PositionSliderState();
}

class _PositionSliderState extends State<PositionSlider> {
  PositionData _positionData = PositionData(
    Duration.zero,
    Duration.zero,
    Duration.zero,
  );
  bool _isDragging = false;
  double _dragValue = 0;
  Object? _currentMediaId;

  @override
  Widget build(BuildContext context) {
    final minimal = PlayerChrome.minimalOf(context);
    final colorScheme = Theme.of(context).colorScheme;
    return StreamBuilder<PositionData>(
      stream: TickerMode.valuesOf(context).enabled
          ? audioHandler.positionDataStream
          : const Stream.empty(),
      initialData: audioHandler.currentPositionData,
      builder: (context, snapshot) {
        final mediaId = audioHandler.mediaItem.valueOrNull?.id;
        if (mediaId != _currentMediaId) {
          _currentMediaId = mediaId;
          _positionData = PositionData(
            Duration.zero,
            Duration.zero,
            Duration.zero,
          );
        }

        if (snapshot.data != null) {
          _positionData = snapshot.data!;
        }

        final maxDuration = _positionData.duration.inSeconds > 0
            ? _positionData.duration.inSeconds.toDouble()
            : 1.0;

        final currentValue = _isDragging
            ? _dragValue
            : _positionData.position.inSeconds.toDouble();

        final slider = SliderTheme(
          data: SliderTheme.of(context).copyWith(
            padding: EdgeInsets.zero,
            trackHeight: minimal ? (widget.inline ? 4 : 5) : null,
            trackShape: minimal ? const RoundedRectSliderTrackShape() : null,
            // The thumb makes the bar easy to find and to grab; the short bar
            // of the mini player has none.
            thumbShape: minimal
                ? RoundSliderThumbShape(
                    enabledThumbRadius: widget.inline ? 0 : 6,
                    elevation: 0,
                    pressedElevation: 0,
                  )
                : null,
            thumbColor: minimal ? colorScheme.onSurface : null,
            overlayShape: minimal
                ? const RoundSliderOverlayShape(overlayRadius: 8)
                : null,
            activeTrackColor: minimal ? colorScheme.onSurface : null,
            inactiveTrackColor: minimal
                ? colorScheme.onSurface.withValues(alpha: 0.2)
                : null,
          ),
          child: SizedBox(
            height: minimal ? (widget.inline ? 16 : 28) : null,
            child: Slider(
              value: currentValue.clamp(0.0, maxDuration),
              onChanged: (value) {
                setState(() {
                  _isDragging = true;
                  _dragValue = value;
                });
              },
              onChangeEnd: (value) {
                audioHandler.seek(Duration(seconds: value.toInt()));
                setState(() {
                  _isDragging = false;
                });
              },
              max: maxDuration,
              semanticFormatterCallback: (value) =>
                  formatDuration(value.toInt()),
            ),
          ),
        );

        if (widget.inline) {
          final style = _timeStyle(context, size: 11);
          return Row(
            children: [
              Text(_positionText(_positionData), style: style),
              const SizedBox(width: 10),
              Expanded(child: slider),
              const SizedBox(width: 10),
              Text(_durationText(_positionData), style: style),
            ],
          );
        }

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            slider,
            SizedBox(height: minimal ? 4 : 8),
            _buildPositionRow(context, _positionData),
          ],
        );
      },
    );
  }

  String _positionText(PositionData positionData) => formatDuration(
    _isDragging ? _dragValue.toInt() : positionData.position.inSeconds,
  );

  String _durationText(PositionData positionData) =>
      formatDuration(positionData.duration.inSeconds);

  /// The times' style: figures of one width, so they do not shift as they
  /// change.
  TextStyle _timeStyle(BuildContext context, {required double size}) =>
      TextStyle(
        fontSize: size,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  Widget _buildPositionRow(BuildContext context, PositionData positionData) {
    final minimal = PlayerChrome.minimalOf(context);
    final textStyle = minimal
        ? _timeStyle(context, size: 12)
        : const TextStyle(fontSize: 15);

    return Stack(
      alignment: Alignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_positionText(positionData), style: textStyle),
            Text(_durationText(positionData), style: textStyle),
          ],
        ),
        AudioQualityBadge(style: textStyle),
      ],
    );
  }
}
