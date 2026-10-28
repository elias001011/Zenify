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
import 'package:musify/services/playlist_download_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/mediaitem.dart';
import 'package:musify/utilities/playlist_dialogs.dart';
import 'package:musify/widgets/desktop_volume_control.dart';
import 'package:musify/widgets/floating_surface.dart';

/// Side panels of the player: shown beside it on wide screens, as sheets on
/// phones.
enum PlayerPanel { queue, lyrics }

/// The player's actions besides playback: lyrics, queue, volume, sleep
/// timer, download, add to playlist and like.
class PlayerActions extends StatefulWidget {
  const PlayerActions({
    super.key,
    required this.metadata,
    required this.panel,
    required this.onPanel,
  });

  final MediaItem metadata;

  /// The panel open beside the player, highlighted.
  final PlayerPanel? panel;

  /// Given a context under the player's scaffold, which sheets need.
  final void Function(PlayerPanel panel, BuildContext context) onPanel;

  @override
  State<PlayerActions> createState() => _PlayerActionsState();
}

class _PlayerActionsState extends State<PlayerActions> {
  late final ValueNotifier<bool> _songLikeStatus;
  late final ValueNotifier<bool> _songOfflineStatus;
  String? get audioId => widget.metadata.extras?['ytid'];
  bool get isRadioStation => widget.metadata.extras?['isLive'] ?? false;

  @override
  void initState() {
    super.initState();
    if (isRadioStation) {
      _songLikeStatus = ValueNotifier<bool>(isRadioStationLiked(audioId ?? ''));
      userLikedRadioStations.addListener(_syncRadioLikeStatus);
    } else {
      _songLikeStatus = ValueNotifier<bool>(isSongAlreadyLiked(audioId));
      userLikedSongsList.addListener(_syncLikeStatus);
    }
    _songOfflineStatus = ValueNotifier<bool>(isSongAlreadyOffline(audioId));
    userOfflineSongs.addListener(_syncOfflineStatus);
  }

  void _syncLikeStatus() {
    final newStatus = isSongAlreadyLiked(audioId);
    if (_songLikeStatus.value != newStatus) {
      _songLikeStatus.value = newStatus;
    }
  }

  void _syncRadioLikeStatus() {
    final newStatus = isRadioStationLiked(audioId ?? '');
    if (_songLikeStatus.value != newStatus) {
      _songLikeStatus.value = newStatus;
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
    final oldAudioId = oldWidget.metadata.extras?['ytid'];
    final oldRadio = oldWidget.metadata.extras?['isLive'] == true;
    if (oldRadio != isRadioStation) {
      if (oldRadio) {
        userLikedRadioStations.removeListener(_syncRadioLikeStatus);
        userLikedSongsList.addListener(_syncLikeStatus);
      } else {
        userLikedSongsList.removeListener(_syncLikeStatus);
        userLikedRadioStations.addListener(_syncRadioLikeStatus);
      }
    }
    if (oldAudioId != audioId || oldRadio != isRadioStation) {
      if (isRadioStation) {
        _songLikeStatus.value = isRadioStationLiked(audioId ?? '');
      } else {
        _songLikeStatus.value = isSongAlreadyLiked(audioId);
      }
      _songOfflineStatus.value = isSongAlreadyOffline(audioId);
    }
  }

  @override
  void dispose() {
    if (isRadioStation) {
      userLikedRadioStations.removeListener(_syncRadioLikeStatus);
    } else {
      userLikedSongsList.removeListener(_syncLikeStatus);
    }
    userOfflineSongs.removeListener(_syncOfflineStatus);
    _songLikeStatus.dispose();
    _songOfflineStatus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n!;
    final online = !offlineMode.value;
    final actionAudioId = audioId;

    return StreamBuilder<List<Map>>(
      stream: audioHandler.queueAsMapStream,
      builder: (context, snapshot) {
        final queue = snapshot.data ?? const [];
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (online && !isRadioStation)
              _ActionButton(
                icon: FluentIcons.text_quote_24_regular,
                tooltip: l10n.lyrics,
                active: widget.panel == PlayerPanel.lyrics,
                onPressed: () => widget.onPanel(PlayerPanel.lyrics, context),
              ),
            if (queue.isNotEmpty && !isRadioStation)
              _ActionButton(
                icon: FluentIcons.apps_list_24_regular,
                tooltip: l10n.queue,
                active: widget.panel == PlayerPanel.queue,
                onPressed: () => widget.onPanel(PlayerPanel.queue, context),
              ),
            if (supportsDesktopVolumeControl) const DesktopVolumeButton(),
            ValueListenableBuilder<Duration?>(
              valueListenable: sleepTimerNotifier,
              builder: (context, timer, _) => _ActionButton(
                icon: FluentIcons.timer_24_regular,
                activeIcon: FluentIcons.timer_24_filled,
                tooltip: l10n.sleepTimer,
                active: timer != null,
                onPressed: () => _onSleepTimer(context, timer != null),
              ),
            ),
            if (!isRadioStation)
              ValueListenableBuilder<bool>(
                valueListenable: _songOfflineStatus,
                builder: (context, offline, _) => _ActionButton(
                  icon: FluentIcons.cloud_arrow_down_24_regular,
                  activeIcon: FluentIcons.cloud_off_24_filled,
                  tooltip: l10n.makeOffline,
                  active: offline,
                  onPressed: audioId == null
                      ? null
                      : () => _toggleOffline(
                          _songOfflineStatus,
                          audioId,
                          widget.metadata,
                          isCurrent: () => mounted && audioId == actionAudioId,
                        ),
                ),
              ),
            if (online && !isRadioStation)
              _ActionButton(
                icon: FluentIcons.album_add_24_regular,
                tooltip: l10n.addToPlaylist,
                onPressed: () => showAddToPlaylistDialog(
                  context,
                  song: mediaItemToMap(widget.metadata),
                ),
              ),
            if (online)
              ValueListenableBuilder<bool>(
                valueListenable: _songLikeStatus,
                builder: (context, liked, _) => _ActionButton(
                  icon: FluentIcons.heart_24_regular,
                  activeIcon: FluentIcons.heart_24_filled,
                  tooltip: l10n.likedSongs,
                  active: liked,
                  activeColor: colorScheme.primary,
                  onPressed: _toggleLike,
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _toggleLike() async {
    final id = audioId;
    if (id == null) return;

    final originalValue = _songLikeStatus.value;
    _songLikeStatus.value = !originalValue;

    try {
      if (isRadioStation) {
        if (originalValue) {
          await removeRadioStationFromLiked(id);
        } else {
          await addRadioStationToLiked(id);
        }
      } else {
        await updateSongLikeStatus(
          audioId,
          !originalValue,
          songData: mediaItemToMap(widget.metadata),
        );
      }
    } catch (e) {
      if (mounted && audioId == id) _songLikeStatus.value = originalValue;
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

/// The actions in a wide floating bar that scrolls sideways when they do
/// not fit, in the island's style.
class PlayerActionBar extends StatelessWidget {
  const PlayerActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FloatingSurface(
      child: SizedBox(
        height: 64,
        child: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.activeIcon,
    this.active = false,
    this.activeColor,
  });

  final IconData icon;
  final IconData? activeIcon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool active;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = activeColor ?? colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        icon: Icon(
          active ? activeIcon ?? icon : icon,
          color: active ? color : colorScheme.onSurfaceVariant,
        ),
        iconSize: 24,
        tooltip: tooltip,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          backgroundColor: active
              ? color.withValues(alpha: 0.15)
              : Colors.transparent,
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
  final originalValue = status.value;
  status.value = !originalValue;

  try {
    final bool success;
    if (originalValue) {
      success =
          !(audioId == null) &&
          await OfflinePlaylistService().removeSongFromOfflineAndResync(
            audioId,
          );
    } else {
      success = await makeSongOffline(mediaItemToMap(metadata));
    }
    if (!success && isCurrent()) {
      status.value = originalValue;
    }
  } catch (e) {
    if (isCurrent()) status.value = originalValue;
    logger.log('Error toggling offline status', error: e);
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
                        label: Text('$mins min'),
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
