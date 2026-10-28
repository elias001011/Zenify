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
import 'package:musify/main.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/download_manager.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/widgets/floating_island.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:musify/widgets/section_header.dart';
import 'package:musify/widgets/song_bar.dart';

/// The download manager: what is downloading, what failed and what finished.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  static const double _maxWidth = 880;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final manager = DownloadManager.instance;

    return ValueListenableBuilder<List<DownloadEntry>>(
      valueListenable: manager.entries,
      builder: (context, entries, _) {
        final downloading = <DownloadEntry>[];
        final failed = <DownloadEntry>[];
        final done = <DownloadEntry>[];
        for (final entry in entries) {
          switch (entry.status) {
            case DownloadStatus.downloading:
              downloading.add(entry);
            case DownloadStatus.failed:
              failed.add(entry);
            case DownloadStatus.done:
              done.add(entry);
          }
        }

        return IslandScaffold(
          title: l10n.downloads,
          globalSearch: false,
          actions: [
            if (failed.isNotEmpty || done.isNotEmpty)
              IconButton(
                icon: const Icon(FluentIcons.delete_24_regular),
                tooltip: l10n.downloadsClearHistory,
                onPressed: manager.clearHistory,
              ),
          ],
          body: entries.isEmpty
              ? _buildEmpty(context)
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final side =
                        (constraints.maxWidth - _maxWidth).clamp(
                              0.0,
                              double.infinity,
                            ) /
                            2 +
                        commonSingleChildScrollViewPadding.left;
                    return CustomScrollView(
                      slivers: [
                        const SliverIslandTopSpace(),
                        SliverPadding(
                          padding: EdgeInsets.symmetric(horizontal: side),
                          sliver: SliverMainAxisGroup(
                            slivers: [
                              ..._section(
                                l10n.downloadsActive,
                                FluentIcons.arrow_download_24_filled,
                                downloading,
                              ),
                              ..._section(
                                l10n.downloadsFailed,
                                FluentIcons.error_circle_24_filled,
                                failed,
                                action: TextButton(
                                  onPressed: () => _retryAll(failed),
                                  child: Text(l10n.downloadsRetryAll),
                                ),
                              ),
                              ..._section(
                                l10n.downloadsDone,
                                FluentIcons.checkmark_circle_24_filled,
                                done,
                              ),
                            ],
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 20)),
                        const SliverMiniPlayerBottomSpace(),
                      ],
                    );
                  },
                ),
        );
      },
    );
  }

  /// Built lazily, like playlist songs, with the app's own song rows.
  List<Widget> _section(
    String title,
    IconData icon,
    List<DownloadEntry> entries, {
    Widget? action,
  }) {
    if (entries.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: SectionHeader(title: title, icon: icon, actionButton: action),
      ),
      SliverList.builder(
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return RepaintBoundary(
            key: ValueKey(entry),
            child: SongBar(
              entry.song,
              true,
              borderRadius: getItemBorderRadius(index, entries.length),
              onPlay: () => audioHandler.playPlaylistSong(
                playlist: {
                  'title': title,
                  'list': [for (final entry in entries) entry.song],
                },
                songIndex: index,
              ),
              trailing: _DownloadStatus(entry),
            ),
          );
        },
      ),
    ];
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

bool _retryingAll = false;

/// One at a time, like a playlist download, however many failed.
Future<void> _retryAll(List<DownloadEntry> failed) async {
  if (_retryingAll) return;
  _retryingAll = true;
  try {
    for (final entry in failed) {
      // Skips songs retried on their own meanwhile (a new entry replaced it).
      if (DownloadManager.instance.entries.value.contains(entry)) {
        await makeSongOffline(entry.song);
      }
    }
  } finally {
    _retryingAll = false;
  }
}

/// A download's state beside its song: progress, a retry button that tells
/// why it failed, or a check with the time it finished.
class _DownloadStatus extends StatelessWidget {
  const _DownloadStatus(this.entry);

  final DownloadEntry entry;

  static String _failureText(AppLocalizations l10n, DownloadFailure? failure) =>
      switch (failure) {
        DownloadFailure.unavailable => l10n.downloadFailedUnavailable,
        DownloadFailure.network => l10n.downloadFailedNetwork,
        _ => l10n.downloadFailedOther,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final colorScheme = Theme.of(context).colorScheme;

    return switch (entry.status) {
      DownloadStatus.downloading => Padding(
        padding: const EdgeInsets.all(10),
        child: ValueListenableBuilder<double?>(
          valueListenable: entry.progress,
          builder: (context, progress, _) => SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(value: progress, strokeWidth: 3),
          ),
        ),
      ),
      DownloadStatus.failed => IconButton(
        icon: Icon(
          FluentIcons.arrow_clockwise_24_regular,
          color: colorScheme.error,
        ),
        tooltip: '${_failureText(l10n, entry.failure)}\n${l10n.downloadsRetry}',
        onPressed: () => makeSongOffline(entry.song),
      ),
      DownloadStatus.done => Tooltip(
        message: _finishedAt(context),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            FluentIcons.checkmark_circle_24_regular,
            color: colorScheme.primary,
          ),
        ),
      ),
    };
  }

  String _finishedAt(BuildContext context) {
    final material = MaterialLocalizations.of(context);
    return '${material.formatShortDate(entry.time)} '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(entry.time))}';
  }
}
