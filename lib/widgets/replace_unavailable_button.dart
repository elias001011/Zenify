/*
 *     Copyright (C) 2025 Valeri Gokadze
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
import 'package:musify/extensions/l10n.dart';
import 'package:musify/services/song_replacement.dart';
import 'package:musify/utilities/flutter_toast.dart';

/// Swaps unavailable [songs] for other uploads and downloads those (see
/// [replaceUnavailableSongs]). The same button in a playlist's notice, with
/// its [playlistId], and in the Downloads tab, for every playlist.
class ReplaceUnavailableButton extends StatefulWidget {
  const ReplaceUnavailableButton({
    super.key,
    required this.songs,
    this.playlistId,
    this.filled = true,
    this.replace = replaceUnavailableSongs,
  });

  final List<Map> songs;
  final String? playlistId;

  final bool filled;

  /// What does the swap; a stand-in lets tests leave storage alone.
  final Future<int> Function(List<Map> songs, {String? playlistId}) replace;

  @override
  State<ReplaceUnavailableButton> createState() =>
      _ReplaceUnavailableButtonState();
}

class _ReplaceUnavailableButtonState extends State<ReplaceUnavailableButton> {
  var _replacing = false;

  Future<void> _replace() async {
    final l10n = context.l10n!;
    setState(() => _replacing = true);
    String message;
    try {
      final replaced = await widget.replace(
        widget.songs,
        playlistId: widget.playlistId,
      );
      message = replaced > 0
          ? l10n.songsReplaced(replaced)
          : l10n.noReplacementFound;
    } on ReplacementSearchFailed {
      message = l10n.replaceNoConnection;
    } finally {
      if (mounted) setState(() => _replacing = false);
    }
    if (mounted) showToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final label = _replacing
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Text(context.l10n!.replaceUnavailable);
    final onPressed = _replacing ? null : _replace;
    return widget.filled
        ? FilledButton(onPressed: onPressed, child: label)
        : TextButton(onPressed: onPressed, child: label);
  }
}
