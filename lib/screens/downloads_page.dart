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
import 'package:musify/constants/app_constants.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/download_manager.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/mediaitem.dart';
import 'package:musify/widgets/floating_island.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:musify/widgets/section_header.dart';
import 'package:musify/widgets/song_artwork.dart';

/// The download manager: what is downloading, what failed and what finished.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final manager = DownloadManager.instance;

    return ValueListenableBuilder<List<DownloadEntry>>(
      valueListenable: manager.entries,
      builder: (context, entries, _) {
        List<DownloadEntry> withStatus(DownloadStatus status) =>
            entries.where((entry) => entry.status == status).toList();
        final downloading = withStatus(DownloadStatus.downloading);
        final failed = withStatus(DownloadStatus.failed);
        final done = withStatus(DownloadStatus.done);
        final hasHistory = failed.isNotEmpty || done.isNotEmpty;

        return IslandScaffold(
          title: l10n.downloads,
          globalSearch: false,
          actions: [
            if (hasHistory)
              IconButton(
                icon: const Icon(FluentIcons.delete_24_regular),
                tooltip: l10n.downloadsClearHistory,
                onPressed: manager.clearHistory,
              ),
          ],
          body: entries.isEmpty
              ? _buildEmpty(context)
              : SingleChildScrollView(
                  padding: withIslandInset(
                    context,
                    commonSingleChildScrollViewPadding,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 880),
                      child: Column(
                        children: [
                          if (downloading.isNotEmpty)
                            _Section(
                              title: l10n.downloadsActive,
                              icon: FluentIcons.arrow_download_24_filled,
                              entries: downloading,
                            ),
                          if (failed.isNotEmpty)
                            _Section(
                              title: l10n.downloadsFailed,
                              icon: FluentIcons.error_circle_24_filled,
                              entries: failed,
                              action: TextButton(
                                onPressed: () {
                                  for (final entry in failed) {
                                    makeSongOffline(entry.song);
                                  }
                                },
                                child: Text(l10n.downloadsRetryAll),
                              ),
                            ),
                          if (done.isNotEmpty)
                            _Section(
                              title: l10n.downloadsDone,
                              icon: FluentIcons.checkmark_circle_24_filled,
                              entries: done,
                            ),
                          const SizedBox(height: 20),
                          const MiniPlayerBottomSpace(),
                        ],
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.arrow_download_24_regular,
              size: 48,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n!.downloadsEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.entries,
    this.action,
  });

  final String title;
  final IconData icon;
  final List<DownloadEntry> entries;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionHeader(title: title, icon: icon, actionButton: action),
        for (var i = 0; i < entries.length; i++)
          _DownloadRow(
            entry: entries[i],
            borderRadius: getItemBorderRadius(i, entries.length),
          ),
      ],
    );
  }
}

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({required this.entry, required this.borderRadius});

  final DownloadEntry entry;
  final BorderRadius borderRadius;

  static String failureText(AppLocalizations l10n, DownloadFailure? failure) =>
      switch (failure) {
        DownloadFailure.unavailable => l10n.downloadFailedUnavailable,
        DownloadFailure.network => l10n.downloadFailedNetwork,
        _ => l10n.downloadFailedOther,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final colorScheme = Theme.of(context).colorScheme;
    final song = entry.song;
    final material = MaterialLocalizations.of(context);
    final time =
        '${material.formatShortDate(entry.time)} '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(entry.time))}';

    final subtitle = switch (entry.status) {
      DownloadStatus.downloading => song['artist']?.toString() ?? '',
      DownloadStatus.failed => failureText(l10n, entry.failure),
      DownloadStatus.done => '${song['artist'] ?? ''} · $time',
    };

    final trailing = switch (entry.status) {
      DownloadStatus.downloading => ValueListenableBuilder<double?>(
        valueListenable: entry.progress,
        builder: (context, progress, _) => SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(value: progress, strokeWidth: 3),
        ),
      ),
      DownloadStatus.failed => FilledButton.tonal(
        onPressed: () => makeSongOffline(song),
        child: Text(l10n.downloadsRetry),
      ),
      DownloadStatus.done => Icon(
        FluentIcons.checkmark_circle_24_regular,
        color: colorScheme.primary,
      ),
    };

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: [
            SongArtworkWidget(size: 48, metadata: mapToMediaItem(song)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song['title']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: entry.status == DownloadStatus.failed
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}
