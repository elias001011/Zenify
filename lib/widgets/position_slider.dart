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
    final colorScheme = Theme.of(context).colorScheme;
    return StreamBuilder<PositionData>(
      stream: audioHandler.positionDataStream,
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

        // With the Mix, the end of the bar from where the next song comes in.
        final mixFrom = audioHandler.mixOutStart.value;
        final mixZone =
            mixFrom != null && _positionData.duration > Duration.zero
            ? mixFrom.inMilliseconds / _positionData.duration.inMilliseconds
            : null;

        final slider = SliderTheme(
          data: SliderTheme.of(context).copyWith(
            padding: EdgeInsets.zero,
            trackHeight: widget.inline ? 4 : 5,
            trackShape: mixZone != null && mixZone < 1
                ? _MixTrackShape(mixZone, colorScheme.primary)
                : const RoundedRectSliderTrackShape(),
            // The thumb makes the bar easy to find and to grab; the short bar
            // of the mini player has none.
            thumbShape: RoundSliderThumbShape(
              enabledThumbRadius: widget.inline ? 0 : 6,
              elevation: 0,
              pressedElevation: 0,
            ),
            thumbColor: colorScheme.onSurface,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 8),
            activeTrackColor: colorScheme.onSurface,
            inactiveTrackColor: colorScheme.onSurface.withValues(alpha: 0.2),
          ),
          child: SizedBox(
            height: widget.inline ? 16 : 28,
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
            const SizedBox(height: 4),
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
    final textStyle = _timeStyle(context, size: 12);

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

/// The usual track, with the stretch where the Mix brings the next song in
/// painted in the accent colour.
class _MixTrackShape extends RoundedRectSliderTrackShape {
  const _MixTrackShape(this.from, this.color);

  /// Where the stretch starts, from 0 to 1 of the track.
  final double from;
  final Color color;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
    final track = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    // Only what is still to play: the played part keeps its colour.
    final left = (track.left + track.width * from).clamp(
      thumbCenter.dx,
      track.right,
    );
    if (track.right - left < 1) return;
    context.canvas.drawRRect(
      RRect.fromLTRBAndCorners(
        left,
        track.top,
        track.right,
        track.bottom,
        topRight: Radius.circular(track.height / 2),
        bottomRight: Radius.circular(track.height / 2),
      ),
      Paint()..color = color,
    );
  }
}
