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
import 'package:musify/services/moods/moods_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';

/// Starts a radio from an artist or a playlist (see
/// [MoodsService.playRadio]). Online only: the radio comes from YouTube
/// Music.
class StartRadioButton extends StatefulWidget {
  const StartRadioButton({
    super.key,
    required this.seeds,
    required this.name,
    this.perArtist = 3,
  });

  /// The songs to start from, read on the tap.
  final List<Map> Function() seeds;

  /// The artist's or the playlist's name, for the queue's title.
  final String name;
  final int perArtist;

  @override
  State<StartRadioButton> createState() => _StartRadioButtonState();
}

class _StartRadioButtonState extends State<StartRadioButton> {
  bool _starting = false;

  Future<void> _start() async {
    if (offlineMode.value) return;
    setState(() => _starting = true);
    final l10n = context.l10n!;
    final started = await moodsService
        .playRadio(
          widget.seeds(),
          title: l10n.radioOf(widget.name),
          perArtist: widget.perArtist,
        )
        .catchError((_) => false);
    if (!mounted) return;
    setState(() => _starting = false);
    if (!started && !offlineMode.value)
      showToast(context, l10n.radioUnavailable);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: offlineMode,
    builder: (context, offline, _) =>
        offline ? const SizedBox.shrink() : _buildButton(context),
  );

  Widget _buildButton(BuildContext context) {
    return IconButton.filledTonal(
      icon: _starting
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(FluentIcons.live_24_regular),
      iconSize: 24,
      onPressed: _starting ? null : _start,
      tooltip: context.l10n!.startRadio,
    );
  }
}
