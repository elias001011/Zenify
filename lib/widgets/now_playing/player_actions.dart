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

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/download_manager.dart';
import 'package:musify/services/local_files_service.dart';
import 'package:musify/services/playlist_download_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/mediaitem.dart';
import 'package:musify/utilities/playlist_dialogs.dart';
import 'package:musify/widgets/desktop_volume_control.dart';
import 'package:musify/widgets/download_progress_icon.dart';

/// Side panels of the player: shown beside it on wide screens, as sheets on
/// phones.
enum PlayerPanel { queue, lyrics }

/// The player's actions besides playback: lyrics, queue, sleep timer,
/// download, add to playlist and, on desktop, volume at the end. A song is
/// liked from the add to playlist dialog; a radio station, which has no
/// playlists, has a heart.
class PlayerActions extends StatefulWidget {
  const PlayerActions({
    super.key,
    required this.metadata,
    this.panel,
    this.onPanel,
    this.miniPlayer = false,
    this.showAddToPlaylist = true,
  });

  final MediaItem metadata;
  final bool miniPlayer;

  /// Off where the button sits beside the song instead.
  final bool showAddToPlaylist;

  /// The panel open beside the player, highlighted.
  final PlayerPanel? panel;

  /// Opens or closes [PlayerPanel] beside the player.
  final ValueChanged<PlayerPanel>? onPanel;

  @override
  State<PlayerActions> createState() => _PlayerActionsState();
}

class _PlayerActionsState extends State<PlayerActions> {
  late final ValueNotifier<bool> _radioLikeStatus;
  late final ValueNotifier<bool> _songOfflineStatus;
  String? get audioId => widget.metadata.extras?['ytid']?.toString();
  bool get isRadioStation => widget.metadata.extras?['isLive'] == true;

  @override
  void initState() {
    super.initState();
    _radioLikeStatus = ValueNotifier<bool>(isRadioStationLiked(audioId ?? ''));
    userLikedRadioStations.addListener(_syncRadioLikeStatus);
    _songOfflineStatus = ValueNotifier<bool>(isSongAlreadyOffline(audioId));
    userOfflineSongs.addListener(_syncOfflineStatus);
    offlineMode.addListener(_onOfflineChanged);
  }

  void _onOfflineChanged() => setState(() {});

  void _syncRadioLikeStatus() {
    final newStatus = isRadioStationLiked(audioId ?? '');
    if (_radioLikeStatus.value != newStatus) {
      _radioLikeStatus.value = newStatus;
    }
  }

  void _syncOfflineStatus() {
    final newStatus = isSongAlreadyOffline(audioId);
    if (_songOfflineStatus.value != newStatus) {
      _songOfflineStatus.value = newStatus;
    }
  }

  @override
  void didUpdateWidget(PlayerActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldAudioId = oldWidget.metadata.extras?['ytid']?.toString();
    if (oldAudioId != audioId) {
      _radioLikeStatus.value = isRadioStationLiked(audioId ?? '');
      _songOfflineStatus.value = isSongAlreadyOffline(audioId);
    }
  }

  @override
  void dispose() {
    userLikedRadioStations.removeListener(_syncRadioLikeStatus);
    offlineMode.removeListener(_onOfflineChanged);
    userOfflineSongs.removeListener(_syncOfflineStatus);
    _radioLikeStatus.dispose();
    _songOfflineStatus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final online = !offlineMode.value;
    // Local files are only played: no offline copy, playlist or like.
    final local = isLocalSongId(audioId);
    final actionAudioId = audioId;

    Widget actions(bool hasQueue) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // A local file has no lyrics to look up, so it gets no button,
        // unless the panel is open: then the button is how to close it.
        if (!widget.miniPlayer &&
            widget.onPanel != null &&
            ((online && !isRadioStation && !local) ||
                widget.panel == PlayerPanel.lyrics))
          PlayerActionButton(
            icon: FluentIcons.text_quote_24_regular,
            tooltip: l10n.lyrics,
            active: widget.panel == PlayerPanel.lyrics,
            onPressed: () => widget.onPanel?.call(PlayerPanel.lyrics),
          ),
        if (!widget.miniPlayer &&
            widget.onPanel != null &&
            hasQueue &&
            !isRadioStation)
          PlayerActionButton(
            icon: FluentIcons.apps_list_24_regular,
            tooltip: l10n.queue,
            active: widget.panel == PlayerPanel.queue,
            onPressed: () => widget.onPanel?.call(PlayerPanel.queue),
          ),
        ValueListenableBuilder<Duration?>(
          valueListenable: sleepTimerNotifier,
          builder: (context, timer, _) => PlayerActionButton(
            icon: FluentIcons.timer_24_regular,
            activeIcon: FluentIcons.timer_24_filled,
            tooltip: l10n.sleepTimer,
            active: timer != null,
            onPressed: () => _onSleepTimer(context, timer != null),
          ),
        ),
        if (!isRadioStation && !local)
          // From the download manager, for whichever song this is: it shows
          // the download of this song, and only of this one, wherever it was
          // started and whatever the player did meanwhile.
          ListenableBuilder(
            listenable: Listenable.merge([
              _songOfflineStatus,
              DownloadManager.instance.entries,
            ]),
            builder: (context, _) {
              final download = DownloadManager.instance.activeFor(audioId);
              return PlayerActionButton(
                icon: FluentIcons.cloud_arrow_down_24_regular,
                activeIcon: FluentIcons.cloud_off_24_filled,
                tooltip: download != null
                    ? l10n.cancelDownload
                    : _songOfflineStatus.value
                    ? l10n.removeOffline
                    : l10n.makeOffline,
                active: _songOfflineStatus.value,
                busy: download == null ? null : DownloadProgressIcon(download),
                onPressed: audioId == null
                    ? null
                    : download != null
                    ? () => DownloadManager.instance.cancel(audioId)
                    : () => _toggleOffline(
                        _songOfflineStatus,
                        audioId,
                        widget.metadata,
                        isCurrent: () => mounted && audioId == actionAudioId,
                      ),
              );
            },
          ),
        if (widget.showAddToPlaylist)
          AddToPlaylistButton(metadata: widget.metadata),
        if (online && isRadioStation)
          ValueListenableBuilder<bool>(
            valueListenable: _radioLikeStatus,
            builder: (context, liked, _) => PlayerActionButton(
              icon: FluentIcons.heart_24_regular,
              activeIcon: FluentIcons.heart_24_filled,
              tooltip: l10n.likedSongs,
              active: liked,
              onPressed: _toggleLike,
            ),
          ),
        // The rightmost icon of the row.
        if (supportsDesktopVolumeControl) const DesktopVolumeButton(),
      ],
    );
    if (widget.miniPlayer) return actions(false);
    return StreamBuilder<List<MediaItem>>(
      initialData: audioHandler.queue.value,
      stream: audioHandler.queue,
      builder: (context, snapshot) =>
          actions(snapshot.data?.isNotEmpty ?? false),
    );
  }

  Future<void> _toggleLike() async {
    final id = audioId;
    if (id == null) return;

    final originalValue = _radioLikeStatus.value;
    _radioLikeStatus.value = !originalValue;

    try {
      if (originalValue) {
        await removeRadioStationFromLiked(id);
      } else {
        await addRadioStationToLiked(id);
      }
    } catch (e) {
      if (mounted && audioId == id) _radioLikeStatus.value = originalValue;
      logger.log('Error toggling like status', error: e);
    }
  }

  Future<void> _onSleepTimer(BuildContext context, bool active) async {
    if (!active) {
      _showSleepTimerDialog(context);
      return;
    }
    await audioHandler.cancelSleepTimer();
    if (!context.mounted) return;
    showToast(
      context,
      context.l10n!.sleepTimerCancelled,
      duration: const Duration(seconds: 1, milliseconds: 500),
    );
  }
}

/// Opens the dialog to put the song in a playlist, or to like it. The icon
/// turns into a filled heart once the song is liked, so the player still shows
/// it. Hidden where there is nothing to add to: a radio station, a local file,
/// offline.
class AddToPlaylistButton extends StatelessWidget {
  const AddToPlaylistButton({
    super.key,
    required this.metadata,
    this.beside = false,
  });

  final MediaItem metadata;

  /// Beside the song: a larger icon, which reaches the edge the progress bar
  /// does.
  final bool beside;

  @override
  Widget build(BuildContext context) {
    final id = metadata.extras?['ytid']?.toString();
    final hidden = metadata.extras?['isLive'] == true || isLocalSongId(id);
    if (hidden) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([offlineMode, userLikedSongsList]),
      builder: (context, _) {
        if (offlineMode.value) return const SizedBox.shrink();
        final button = PlayerActionButton(
          icon: FluentIcons.album_add_24_regular,
          activeIcon: FluentIcons.heart_24_filled,
          tooltip: context.l10n!.addToPlaylist,
          active: isSongAlreadyLiked(id),
          iconSize: beside ? 28 : 24,
          onPressed: () =>
              showAddToPlaylistDialog(context, song: mediaItemToMap(metadata)),
        );
        if (!beside) return button;
        final end = Directionality.of(context) == TextDirection.rtl
            ? -12.0
            : 12.0;
        return Transform.translate(offset: Offset(end, 0), child: button);
      },
    );
  }
}

/// One of the player's action buttons, tinted while [active].
class PlayerActionButton extends StatelessWidget {
  const PlayerActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.activeIcon,
    this.active = false,
    this.busy,
    this.iconSize = 24,
  });

  final IconData icon;
  final IconData? activeIcon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final double iconSize;

  /// Takes the icon's place while something is under way.
  final Widget? busy;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        icon:
            busy ??
            Icon(
              active ? activeIcon ?? icon : icon,
              color: active ? color : colorScheme.onSurfaceVariant,
            ),
        iconSize: iconSize,
        tooltip: tooltip,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          backgroundColor: Colors.transparent,
          side: BorderSide.none,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

Future<void> _toggleOffline(
  ValueNotifier<bool> status,
  String? audioId,
  MediaItem metadata, {
  required bool Function() isCurrent,
}) async {
  // A download is not flipped ahead: the button follows the download manager,
  // which has it queued, running, saved or failed.
  if (!status.value) {
    await makeSongOffline(mediaItemToMap(metadata));
    return;
  }
  status.value = false;
  try {
    final removed =
        audioId != null &&
        await OfflinePlaylistService().removeSongFromOfflineAndResync(audioId);
    if (!removed && isCurrent()) status.value = true;
  } catch (e) {
    if (isCurrent()) status.value = true;
    logger.log('Error removing the offline song', error: e);
  }
}

void _showSleepTimerDialog(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;

  showDialog(
    context: context,
    builder: (context) {
      final duration = sleepTimerNotifier.value ?? Duration.zero;
      var hours = duration.inMinutes ~/ 60;
      var minutes = duration.inMinutes % 60;

      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(FluentIcons.timer_24_regular, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  context.l10n!.sleepTimer,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n!.selectDuration,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                _buildTimeSelector(
                  context: context,
                  label: context.l10n!.hours,
                  value: hours,
                  colorScheme: colorScheme,
                  onDecrement: () {
                    if (hours > 0) setState(() => hours--);
                  },
                  onIncrement: () => setState(() => hours++),
                ),
                const SizedBox(height: 16),
                _buildTimeSelector(
                  context: context,
                  label: context.l10n!.minutes,
                  value: minutes,
                  colorScheme: colorScheme,
                  onDecrement: () {
                    if (minutes > 0) setState(() => minutes--);
                  },
                  onIncrement: () {
                    if (minutes < 59) setState(() => minutes++);
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    ...[15, 30, 45, 60].map((mins) {
                      return ActionChip(
                        label: Text(context.l10n!.minutesShort(mins)),
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        labelStyle: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onPressed: () {
                          setState(() {
                            hours = mins ~/ 60;
                            minutes = mins % 60;
                          });
                        },
                      );
                    }),
                    ActionChip(
                      label: Text(context.l10n!.endOfSong),
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      labelStyle: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onPressed: () {
                        audioHandler.setSleepTimerEndOfSong();
                        showToast(
                          context,
                          context.l10n!.sleepTimerSet,
                          duration: const Duration(
                            seconds: 1,
                            milliseconds: 500,
                          ),
                        );
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  foregroundColor: colorScheme.onSurfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(context.l10n!.cancel),
              ),
              FilledButton(
                onPressed: () {
                  final duration = Duration(hours: hours, minutes: minutes);
                  if (duration.inSeconds > 0) {
                    audioHandler.setSleepTimer(duration);
                    showToast(
                      context,
                      context.l10n!.sleepTimerSet,
                      duration: const Duration(seconds: 1, milliseconds: 500),
                    );
                  }
                  Navigator.pop(context);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(context.l10n!.setTimer),
              ),
            ],
          );
        },
      );
    },
  );
}

Widget _buildTimeSelector({
  required BuildContext context,
  required String label,
  required int value,
  required ColorScheme colorScheme,
  required VoidCallback onDecrement,
  required VoidCallback onIncrement,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w500,
            fontSize: 16,
          ),
        ),
        Row(
          children: [
            IconButton(
              icon: Icon(
                FluentIcons.line_horizontal_1_24_regular,
                color: colorScheme.onSurfaceVariant,
              ),
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: onDecrement,
            ),
            Container(
              width: 48,
              alignment: Alignment.center,
              child: Text(
                '$value',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                FluentIcons.add_24_regular,
                color: colorScheme.onSurfaceVariant,
              ),
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: onIncrement,
            ),
          ],
        ),
      ],
    ),
  );
}
