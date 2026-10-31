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
import 'package:musify/screens/replace_review_page.dart';
import 'package:musify/services/song_replacement.dart';
import 'package:musify/utilities/flutter_toast.dart';

/// Searches replacements for unavailable [songs], shows what was found for
/// the person to check, and swaps and downloads what is accepted. Null when
/// the person backed out; throws [ReplacementSearchFailed] when no search
/// could be made. [ReplaceUnavailableButton] runs it: in a playlist's
/// notice, with its [playlistId], and in the Downloads tab, for every
/// playlist.
Future<int?> reviewAndReplace(
  BuildContext context,
  List<Map> songs, {
  String? playlistId,
}) async {
  if (replacing.value) return null;
  replacing.value = true;
  try {
    final plan = await planReplacements(songs, playlistId: playlistId);
    // Nothing held, or flagged: nothing to show.
    if (plan.songs.isEmpty) return 0;
    if (!context.mounted) return null;
    final swaps = await Navigator.of(context).push<Map<String, Map>>(
      MaterialPageRoute(builder: (_) => ReplaceReviewPage(plan: plan)),
    );
    return swaps == null ? null : await applyReplacements(plan, swaps);
  } finally {
    replacing.value = false;
  }
}

class ReplaceUnavailableButton extends StatefulWidget {
  const ReplaceUnavailableButton({
    super.key,
    required this.songs,
    this.playlistId,
    this.filled = true,
    this.replace = reviewAndReplace,
  });

  final List<Map> songs;
  final String? playlistId;

  final bool filled;

  /// What does the swap: null when the person backed out. A stand-in lets
  /// tests leave storage alone.
  final Future<int?> Function(
    BuildContext context,
    List<Map> songs, {
    String? playlistId,
  })
  replace;

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
        context,
        widget.songs,
        playlistId: widget.playlistId,
      );
      if (replaced == null) return;
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
