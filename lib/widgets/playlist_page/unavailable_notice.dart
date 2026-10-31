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

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/services/unavailable_songs.dart';

/// Tells that some songs of a playlist failed as unavailable on YouTube, and
/// offers to dismiss that or to swap them for other uploads. Songs that are
/// downloaded still play, so they are not counted.
class UnavailableNotice extends StatefulWidget {
  const UnavailableNotice({
    super.key,
    required this.playlistId,
    required this.songs,
    required this.onReplace,
  });

  final String playlistId;
  final List songs;

  /// Replaces the given songs; completes when it is done.
  final Future<void> Function(List<Map> songs) onReplace;

  @override
  State<UnavailableNotice> createState() => _UnavailableNoticeState();
}

class _UnavailableNoticeState extends State<UnavailableNotice> {
  var _replacing = false;
  late final _changes = Listenable.merge([
    unavailableSongs.ids,
    offlineMode,
    userOfflineSongs,
  ]);

  List<Map> get _affected {
    final dismissed = unavailableSongs.dismissed(widget.playlistId);
    return [
      for (final song in widget.songs.whereType<Map>())
        if (unavailableSongs.contains(song['ytid']) &&
            !isSongAlreadyOffline(song['ytid']) &&
            !dismissed.contains(song['ytid'].toString()))
          song,
    ];
  }

  Future<void> _replace(List<Map> songs) async {
    setState(() => _replacing = true);
    try {
      await widget.onReplace(songs);
    } finally {
      if (mounted) setState(() => _replacing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _changes,
      builder: (context, _) {
        final affected = _affected;
        if (offlineMode.value || affected.isEmpty) {
          return const SizedBox.shrink();
        }
        final l10n = context.l10n!;
        final colors = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        FluentIcons.warning_24_regular,
                        color: colors.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.unavailableSongsNotice(affected.length),
                          style: TextStyle(color: colors.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _replacing
                            ? null
                            : () =>
                                  unavailableSongs.dismiss(widget.playlistId, [
                                    for (final s in affected)
                                      s['ytid'].toString(),
                                  ]),
                        child: Text(l10n.dismiss),
                      ),
                      FilledButton(
                        onPressed: _replacing ? null : () => _replace(affected),
                        child: _replacing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(l10n.replaceUnavailable),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
