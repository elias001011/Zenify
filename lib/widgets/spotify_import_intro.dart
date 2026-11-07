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

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/services/router_service.dart';

const _seenKey = 'spotifyImportIntroSeen';

/// Whether the intro was already shown. Kept on this device, outside the
/// backup: a restored library is still new to this install.
bool get spotifyImportIntroSeen =>
    Hive.box('userNoBackup').get(_seenKey, defaultValue: false) == true;

/// Tells, once, that a Spotify playlist can be imported from a CSV file, and
/// offers to go to the import. Either answer ends it for good.
Future<void> showSpotifyImportIntro(BuildContext context) async {
  // Written in the background: the box already answers `seen`.
  unawaited(Hive.box('userNoBackup').put(_seenKey, true).catchError((_) {}));
  final colors = Theme.of(context).colorScheme;
  final import = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(
        FluentIcons.arrow_import_24_regular,
        color: colors.primary,
        size: 40,
      ),
      title: Text(
        context.l10n!.spotifyImportIntroTitle,
        style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600),
        textAlign: TextAlign.center,
      ),
      content: Text(
        context.l10n!.spotifyImportIntroDescription,
        style: TextStyle(color: colors.onSurfaceVariant),
        textAlign: TextAlign.center,
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: colors.outline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(context.l10n!.dismiss),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.l10n!.importAction),
        ),
      ],
    ),
  );
  // `go`, not `push`: the page lives in the Settings tab, and pushing from
  // another tab would leave it behind that tab's own page.
  if (import == true) {
    NavigationManager.router.go('/settings/import-spotify-playlist');
  }
}
