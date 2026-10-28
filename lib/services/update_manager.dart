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

import 'dart:convert';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/constants/version.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/platform_utils.dart';
import 'package:musify/utilities/url_launcher.dart';
import 'package:musify/widgets/auto_format_text.dart';

const String releasesUrl =
    'https://api.github.com/repos/$appRepository/releases/latest';

/// A link the home page shows as an announcement while it is set. Edit
/// `announcement.json` on the default branch to post or clear one.
const String announcementUrl =
    'https://raw.githubusercontent.com/$appRepository/master/announcement.json';

Future<void> fetchAnnouncement() async {
  try {
    final response = await http.get(Uri.parse(announcementUrl));
    if (response.statusCode != 200) return;
    final link = (json.decode(response.body) as Map)['announcementurl'];
    announcementURL.value = link is String && link.isNotEmpty ? link : null;
  } catch (e, stackTrace) {
    logger.log(
      'Error fetching the announcement',
      error: e,
      stackTrace: stackTrace,
    );
  }
}

/// [manual] reports "up to date" and failures, for the Settings entry.
Future<void> checkAppUpdates({bool manual = false}) async {
  void report(String Function(AppLocalizations l10n) message) {
    final context = NavigationManager().context;
    if (manual && context.mounted) showToast(context, message(context.l10n!));
  }

  try {
    final response = await http.get(Uri.parse(releasesUrl));

    if (response.statusCode != 200) {
      logger.log(
        'Fetch update API call returned status code ${response.statusCode}',
      );
      report((l10n) => l10n.updateCheckFailed);
      return;
    }

    final release = json.decode(response.body) as Map<String, dynamic>;
    final latestVersion = release['tag_name'].toString().replaceFirst(
      RegExp('^v'),
      '',
    );

    if (!isLatestVersionHigher(appVersion, latestVersion)) {
      report((l10n) => l10n.appIsUpToDate);
      return;
    }

    final downloadUrl = pickUpdateAsset(release, await preferredUpdateAssets());

    await showDialog(
      context: NavigationManager().context,
      builder: (BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;

        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  FluentIcons.arrow_download_24_regular,
                  color: colorScheme.onPrimaryContainer,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.l10n!.appUpdateIsAvailable,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'V$latestVersion',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height / 2.5,
                ),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SingleChildScrollView(
                  child: AutoFormatText(
                    text: release['body']?.toString() ?? '',
                  ),
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: <Widget>[
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colorScheme.outline),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(context.l10n!.cancel),
            ),
            FilledButton.icon(
              onPressed: () {
                launchURL(Uri.parse(downloadUrl));
                Navigator.pop(context);
              },
              icon: const Icon(FluentIcons.arrow_download_20_regular),
              label: Text(context.l10n!.download),
            ),
          ],
        );
      },
    );
  } catch (e, stackTrace) {
    logger.log('Error in checkAppUpdates', error: e, stackTrace: stackTrace);
    report((l10n) => l10n.updateCheckFailed);
  }
}

void showUpdateCheckDialog(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        icon: Icon(
          FluentIcons.arrow_sync_circle_24_regular,
          color: colorScheme.primary,
          size: 40,
        ),
        title: Text(
          context.l10n!.checkForUpdates,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        content: Text(
          context.l10n!.enableUpdateChecksDescription,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            onPressed: () {
              shouldWeCheckUpdates.value = false;
              addOrUpdateData<bool>('settings', 'shouldWeCheckUpdates', false);
              Navigator.of(context).pop();
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colorScheme.outline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(context.l10n!.no),
          ),
          FilledButton(
            onPressed: () {
              shouldWeCheckUpdates.value = true;
              addOrUpdateData<bool>('settings', 'shouldWeCheckUpdates', true);
              if (!isFdroidBuild && kReleaseMode && !offlineMode.value) {
                checkAppUpdates();
                isUpdateChecked = true;
              }
              Navigator.of(context).pop();
            },
            child: Text(context.l10n!.yes),
          ),
        ],
      );
    },
  );
}

/// Whether [latestVersion] is newer, comparing numbers (`0.1.0-1` > `0.1.0`).
bool isLatestVersionHigher(String appVersion, String latestVersion) {
  List<int> parts(String version) => version
      .split(RegExp(r'[.\-+]'))
      .map((part) => int.tryParse(part) ?? 0)
      .toList();

  final current = parts(appVersion);
  final latest = parts(latestVersion);
  final length = current.length > latest.length
      ? current.length
      : latest.length;
  for (var i = 0; i < length; i++) {
    final a = i < current.length ? current[i] : 0;
    final b = i < latest.length ? latest[i] : 0;
    if (a != b) return b > a;
  }
  return false;
}

Future<String> getCPUArchitecture() async {
  final info = await Process.run('uname', ['-m']);
  return info.stdout.toString().trim();
}

/// Release asset names that fit this install, best first.
Future<List<String>> preferredUpdateAssets() async {
  if (isAndroidPlatform) {
    final arm64 = await getCPUArchitecture() == 'aarch64';
    return [if (arm64) '$appName-arm64-v8a.apk', '$appName.apk'];
  }
  final executable = Platform.resolvedExecutable;
  if (Platform.isLinux) {
    // The .deb installs under /usr/lib; anything else is the tarball.
    return executable.startsWith('/usr/lib/')
        ? ['$appName-linux-x64.deb']
        : ['$appName-linux-x64.tar.gz'];
  }
  if (Platform.isWindows) {
    final installed = File('${File(executable).parent.path}\\unins000.exe')
        .existsSync();
    return installed
        ? ['$appName-windows-x64-setup.exe']
        : ['$appName-windows-x64-portable.zip'];
  }
  return const [];
}

/// The first of [names] attached to [release], or the release page.
String pickUpdateAsset(Map<String, dynamic> release, List<String> names) {
  final assets = <String, String>{
    for (final asset in release['assets'] as List? ?? const [])
      if (asset is Map && asset['browser_download_url'] is String)
        asset['name'].toString(): asset['browser_download_url'] as String,
  };
  for (final name in names) {
    final url = assets[name];
    if (url != null) return url;
  }
  return release['html_url'].toString();
}
