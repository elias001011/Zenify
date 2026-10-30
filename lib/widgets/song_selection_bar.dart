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

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/platform_utils.dart';
import 'package:musify/utilities/playlist_dialogs.dart';
import 'package:musify/widgets/confirmation_dialog.dart';
import 'package:musify/widgets/floating_surface.dart';
import 'package:musify/widgets/song_selection_controller.dart';

/// Wraps a screen so its list can be acted on by the batch: the action bar
/// floats over the content while songs are ticked, and the back gesture
/// leaves selection mode instead of leaving the screen.
class SongSelectionScope extends StatelessWidget {
  const SongSelectionScope({
    super.key,
    required this.controller,
    required this.actionBar,
    required this.child,
  });

  final SongSelectionController controller;
  final Widget actionBar;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      // The screen itself is handed over untouched: ticking a song must not
      // rebuild the whole list, only the bars that listen for it.
      child: child,
      builder: (context, child) => PopScope(
        canPop: !controller.isActive,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) controller.exit();
        },
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): controller.exit,
          },
          child: Stack(
            children: [
              MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: MediaQuery.paddingOf(context).copyWith(
                    bottom:
                        MediaQuery.paddingOf(context).bottom +
                        (controller.isActive ? 132 : 0),
                  ),
                ),
                child: child!,
              ),
              if (controller.isActive)
                Positioned(
                  left: MediaQuery.paddingOf(context).left + 8,
                  right: 8,
                  bottom: MediaQuery.paddingOf(context).bottom + 8,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: actionBar,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The actions offered on the ticked songs.
///
/// Every action replays the unit action of the song overflow menu over
/// [SongSelectionController.selectedSongs], which is kept in the order the
/// songs were ticked.
class SongSelectionBar extends StatelessWidget {
  const SongSelectionBar({
    super.key,
    required this.controller,
    required this.visibleSongs,
    this.showQueueActions = true,
    this.showLikeAction = true,
    this.showPlaylistAction = true,
    this.showOfflineAction = true,
    this.onRemoveSelected,
    this.onMoveSelected,
    this.removeLabel,
  });

  final SongSelectionController controller;

  /// The songs currently on screen, for "select all".
  final List<Map> Function() visibleSongs;

  final bool showQueueActions;
  final bool showLikeAction;
  final bool showPlaylistAction;
  final bool showOfflineAction;

  /// Destructive, so the bar asks for a confirmation before running it.
  final Future<void> Function(List<Map> songs)? onRemoveSelected;

  /// What the removal does on this screen, e.g. "Remove from playlist".
  final String? removeLabel;
  final Future<void> Function(List<Map> songs)? onMoveSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final count = controller.selectedCount;

        return FloatingSurface(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(FluentIcons.dismiss_24_regular),
                      color: colorScheme.onSurface,
                      tooltip: context.l10n!.cancel,
                      onPressed: controller.exit,
                    ),
                    Expanded(
                      child: Text(
                        context.l10n!.songsSelected(count),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => controller.selectAll(visibleSongs()),
                      child: Text(context.l10n!.selectAll),
                    ),
                  ],
                ),
                _SelectionActions(
                  children: _buildActions(context, colorScheme),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildActions(BuildContext context, ColorScheme colorScheme) {
    final l10n = context.l10n!;
    final isOffline = offlineMode.value;

    return [
      if (showQueueActions) ...[
        _action(
          colorScheme: colorScheme,
          icon: FluentIcons.receipt_play_24_regular,
          label: l10n.playNext,
          onPressed: () => _run(context, _playSelectedNext),
        ),
        _action(
          colorScheme: colorScheme,
          icon: FluentIcons.text_bullet_list_add_24_regular,
          label: l10n.addToQueue,
          onPressed: () => _run(context, _addSelectedToQueue),
        ),
      ],
      if (showLikeAction && !isOffline)
        _action(
          colorScheme: colorScheme,
          icon: FluentIcons.heart_24_regular,
          label: l10n.addToLikedSongs,
          onPressed: () => _run(context, _likeSelected),
        ),
      if (showPlaylistAction && !isOffline)
        _action(
          colorScheme: colorScheme,
          icon: FluentIcons.album_add_24_regular,
          label: l10n.addToPlaylist,
          onPressed: () => _addSelectedToPlaylist(context),
        ),
      if (onMoveSelected != null)
        _action(
          colorScheme: colorScheme,
          icon: FluentIcons.folder_arrow_right_24_regular,
          label: l10n.moveToPlaylist,
          onPressed: () => _run(context, (_, songs) => onMoveSelected!(songs)),
        ),
      if (showOfflineAction && !isOffline)
        _action(
          colorScheme: colorScheme,
          icon: FluentIcons.cloud_arrow_down_24_regular,
          label: l10n.makeOffline,
          onPressed: () => _run(context, _makeSelectedOffline),
        ),
      if (onRemoveSelected != null)
        _action(
          colorScheme: colorScheme,
          icon: FluentIcons.delete_24_regular,
          label: removeLabel ?? l10n.remove,
          isDangerous: true,
          onPressed: () => _confirmRemoveSelected(context),
        ),
    ];
  }

  Widget _action({
    required ColorScheme colorScheme,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool isDangerous = false,
  }) {
    final color = isDangerous ? colorScheme.error : colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton.icon(
        onPressed: controller.hasSelection ? onPressed : null,
        style: TextButton.styleFrom(foregroundColor: color),
        icon: Icon(icon, size: 20),
        label: Text(label),
      ),
    );
  }

  /// Runs [action] on the ticked songs, then leaves selection mode.
  void _run(
    BuildContext context,
    Future<void> Function(BuildContext context, List<Map> songs) action,
  ) {
    final songs = controller.selectedSongs;
    if (songs.isEmpty) return;
    // The bar leaves the tree with selection mode, and its context with it,
    // while the action is still running. Its report goes to the messenger,
    // which outlives both.
    final toastContext = ScaffoldMessenger.of(context).context;
    controller.exit();
    unawaited(
      action(toastContext, songs).catchError((Object error, StackTrace stack) {
        logger.log('Batch song action failed', error: error, stackTrace: stack);
        if (toastContext.mounted)
          showToast(toastContext, toastContext.l10n!.error);
      }),
    );
  }

  /// `playNext` inserts right after the track being played, so the selection
  /// is replayed backwards to land in the order it was ticked. With an empty
  /// queue there is nothing to insert after yet: the first ticked song goes in
  /// first and becomes the one the others are inserted after.
  Future<void> _playSelectedNext(BuildContext context, List<Map> songs) async {
    final remaining = List<Map>.of(songs);
    if (audioHandler.currentSong == null) {
      await audioHandler.playNext(remaining.removeAt(0));
    }
    for (final song in remaining.reversed) {
      await audioHandler.playNext(song);
    }
    if (context.mounted) {
      showToast(context, context.l10n!.songsAdded(songs.length));
    }
  }

  Future<void> _addSelectedToQueue(
    BuildContext context,
    List<Map> songs,
  ) async {
    for (final song in songs) {
      await audioHandler.addToQueue(song);
    }
    if (context.mounted) {
      showToast(context, context.l10n!.songsAdded(songs.length));
    }
  }

  Future<void> _likeSelected(BuildContext context, List<Map> songs) async {
    for (final song in songs) {
      await updateSongLikeStatus(song['ytid'], true, songData: song);
    }
    if (context.mounted) {
      showToast(context, context.l10n!.songsAdded(songs.length));
    }
  }

  /// The dialog already knows how to add a whole list, in the given order.
  void _addSelectedToPlaylist(BuildContext context) {
    final songs = controller.selectedSongs;
    if (songs.isEmpty) return;
    // Opened before leaving selection mode: the dialog is pushed from this
    // context, which goes away with the bar.
    showAddToPlaylistDialog(context, songs: songs);
    controller.exit();
  }

  Future<void> _makeSelectedOffline(
    BuildContext context,
    List<Map> songs,
  ) async {
    var downloaded = 0;
    for (final song in songs) {
      if (await makeSongOffline(song)) downloaded++;
    }
    if (context.mounted) {
      showToast(context, context.l10n!.songsAddedToOffline(downloaded));
    }
  }

  void _confirmRemoveSelected(BuildContext context) {
    final songs = controller.selectedSongs;
    final remove = onRemoveSelected;
    if (songs.isEmpty || remove == null) return;

    showDialog(
      context: context,
      builder: (dialogContext) => ConfirmationDialog(
        confirmationMessage: dialogContext.l10n!.removeSelectedSongsQuestion(
          songs.length,
        ),
        submitMessage: removeLabel ?? dialogContext.l10n!.remove,
        isDangerous: true,
        onCancel: () => Navigator.pop(dialogContext),
        onSubmit: () {
          Navigator.pop(dialogContext);
          controller.exit();
          unawaited(remove(songs));
        },
      ),
    );
  }
}

/// Explicit paging for mouse users; touch, trackpad, wheel and keyboard focus
/// can still scroll the same actions without opening a separate menu.
class _SelectionActions extends StatefulWidget {
  const _SelectionActions({required this.children});
  final List<Widget> children;

  @override
  State<_SelectionActions> createState() => _SelectionActionsState();
}

class _SelectionActionsState extends State<_SelectionActions> {
  final _scroll = ScrollController();
  final _edges = ValueNotifier<(bool, bool)>((false, false));

  bool _metrics(ScrollMetrics metrics) {
    _edges.value = (metrics.extentBefore > 1, metrics.extentAfter > 1);
    return false;
  }

  void _page(int direction) {
    final position = _scroll.position;
    unawaited(
      _scroll.animateTo(
        (position.pixels + direction * position.viewportDimension * 0.8).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final delta = event.scrollDelta.dx != 0
          ? event.scrollDelta.dx
          : event.scrollDelta.dy;
      final position = _scroll.position;
      _scroll.jumpTo(
        (position.pixels + delta).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _edges.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actions = Listener(
      onPointerSignal: isDesktopPlatform ? _wheel : null,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: PointerDeviceKind.values.toSet(),
          scrollbars: false,
        ),
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) => _metrics(n.metrics),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) => _metrics(n.metrics),
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: Row(children: widget.children),
            ),
          ),
        ),
      ),
    );
    if (!isDesktopPlatform || MediaQuery.sizeOf(context).width < 600) {
      return actions;
    }
    return ValueListenableBuilder<(bool, bool)>(
      valueListenable: _edges,
      child: actions,
      builder: (context, edges, child) => Row(
        children: [
          IconButton(
            tooltip: MaterialLocalizations.of(context).previousPageTooltip,
            icon: const Icon(FluentIcons.chevron_left_24_regular),
            onPressed: edges.$1 ? () => _page(-1) : null,
          ),
          Expanded(child: child!),
          IconButton(
            tooltip: MaterialLocalizations.of(context).nextPageTooltip,
            icon: const Icon(FluentIcons.chevron_right_24_regular),
            onPressed: edges.$2 ? () => _page(1) : null,
          ),
        ],
      ),
    );
  }
}
