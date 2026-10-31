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
import 'package:musify/services/song_replacement.dart';
import 'package:musify/services/unavailable_songs.dart';
import 'package:musify/widgets/replace_unavailable_button.dart';

final _changes = Listenable.merge([
  unavailableSongs.ids,
  userOfflineSongs,
  replacementOffer,
]);

/// Tells, once a playlist's download is over, that some songs of it failed as
/// unavailable on YouTube, and offers to dismiss that or to swap them for
/// other uploads. Songs that are downloaded still play, so they are not
/// counted.
class UnavailableNotice extends StatelessWidget {
  const UnavailableNotice({
    super.key,
    required this.playlistId,
    required this.songs,
    this.replace = reviewAndReplace,
  });

  final String playlistId;
  final List songs;
  final Future<int?> Function(
    BuildContext context,
    List<Map> songs, {
    String? playlistId,
  })
  replace;

  List<Map> get _affected {
    final dismissed = unavailableSongs.dismissed(playlistId);
    return [
      for (final song in songs.whereType<Map>())
        if (unavailableSongs.contains(song['ytid']) &&
            !isSongAlreadyOffline(song['ytid']) &&
            !dismissed.contains(song['ytid'].toString()))
          song,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _changes,
      builder: (context, _) {
        if (!canOfferReplacement) return const SizedBox.shrink();
        final affected = _affected;
        if (affected.isEmpty) return const SizedBox.shrink();
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
                        onPressed: () => unavailableSongs.dismiss(playlistId, [
                          for (final song in affected) song['ytid'].toString(),
                        ]),
                        child: Text(l10n.dismiss),
                      ),
                      ReplaceUnavailableButton(
                        songs: affected,
                        playlistId: playlistId,
                        replace: replace,
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
