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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/services/mix_analysis.dart';
import 'package:musify/services/mix_edits.dart';
import 'package:musify/services/mix_transition.dart';
import 'package:musify/utilities/media_duration.dart';
import 'package:musify/utilities/platform_utils.dart';
import 'package:musify/widgets/mix_editor.dart';

/// Between two songs of a playlist with the Mix on: the transition they get.
/// "Auto" until both were analysed, then its style and the tempos.
class MixChip extends StatelessWidget {
  const MixChip(this.song, this.next, {super.key, this.playlistId});

  final Map song;
  final Map next;
  final String? playlistId;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final analyzer = audioHandler.mixAnalyzer;
    return ListenableBuilder(
      listenable: Listenable.merge([analyzer.changes, mixEdits.changes]),
      builder: (context, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Center(
          child: Material(
            color: colorScheme.secondaryContainer,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: playlistId == null
                  ? null
                  : () => showMixEditor(context, playlistId!, song, next),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FluentIcons.merge_24_regular,
                      size: 13,
                      color: colorScheme.onSecondaryContainer,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      mixChipLabel(
                        song,
                        next,
                        tail: analyzer.edge(song, tail: true),
                        head: analyzer.edge(next, tail: false),
                        customLabel: context.l10n!.mixCustom,
                        edit: mixEdits.get(
                          playlistId,
                          song['ytid']?.toString(),
                          next['ytid']?.toString(),
                        ),
                      ),
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: colorScheme.onSecondaryContainer),
                    ),
                    if (playlistId != null) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The chip's text: the Automatic style for the pair and the tempos known.
String mixChipLabel(
  Map song,
  Map next, {
  MixEdge? tail,
  MixEdge? head,
  MixEdit? edit,
  String customLabel = 'Custom',
}) {
  final duration = readMediaDuration(song['duration']);
  if (edit == null &&
      (tail == null ||
          head == null ||
          duration == null ||
          duration <= Duration.zero)) {
    return 'Auto';
  }
  final coming = readMediaDuration(next['duration']);
  final style =
      edit?.style ??
      chooseCue(
        duration: duration!,
        coming: coming,
        tail: tail,
        head: head,
        pair: '${song['ytid']}>${next['ytid']}',
        echo: isDesktopPlatform,
      ).style;
  final name =
      edit != null &&
          (edit.volume != null || edit.eq != null || edit.filter != null)
      ? customLabel
      : switch (style) {
          MixStyle.smooth => 'Smooth',
          MixStyle.fadeOut => 'Fade out / in',
          MixStyle.fade => 'Fade',
          MixStyle.rise => 'Rise',
          MixStyle.blend => 'Blend',
          MixStyle.wave => 'Wave',
          MixStyle.melt => 'Melt',
          MixStyle.under => 'Under',
          MixStyle.slam => 'Slam',
          MixStyle.echo => 'Echo',
          MixStyle.sweep => 'Sweep',
        };
  final tempos = [
    if (tail?.rhythmic == true) tail!.bpm.round(),
    if (head?.rhythmic == true) head!.bpm.round(),
  ];
  return switch (tempos.length) {
    2 when tempos[0] == tempos[1] => '$name · ${tempos[0]} BPM',
    2 => '$name · ${tempos[0]} → ${tempos[1]} BPM',
    1 => '$name · ${tempos[0]} BPM',
    _ => name,
  };
}
