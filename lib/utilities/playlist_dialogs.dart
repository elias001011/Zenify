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

import 'dart:math' as math;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/constants/motion.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/local_files_service.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/map_utils.dart';
import 'package:musify/utilities/playlist_image_picker.dart';
import 'package:musify/widgets/click_detector.dart';
import 'package:musify/widgets/dialog_item.dart';
import 'package:musify/widgets/dialog_parts.dart';

void showCreatePlaylistDialog(
  BuildContext context, {
  dynamic songToAdd,
  List<dynamic>? songsToAdd,
}) {
  var id = '';
  var customPlaylistName = '';
  var isYouTubeMode = songToAdd == null && songsToAdd == null;
  String? imageUrl;
  String? imageBase64;

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, dialogSetState) {
          final colorScheme = Theme.of(context).colorScheme;

          Future<void> _pickImage() async {
            final result = await pickImage();
            if (result != null) {
              dialogSetState(() {
                imageBase64 = result;
                imageUrl = null;
              });
            }
          }

          Widget _imagePreview() {
            return buildImagePreview(
              imageBase64: imageBase64,
              imageUrl: imageUrl,
            );
          }

          return AlertDialog(
            icon: const DialogIconHeader(icon: FluentIcons.add_24_filled),
            title: Text(
              context.l10n!.addPlaylist,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 20,
              ),
              textAlign: TextAlign.center,
            ),
            titleTextStyle: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (songToAdd == null && songsToAdd == null)
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Expanded(
                            child: ClickDetector(
                              onTap: () {
                                dialogSetState(() {
                                  isYouTubeMode = true;
                                  id = '';
                                  customPlaylistName = '';
                                  imageUrl = null;
                                  imageBase64 = null;
                                });
                              },
                              child: AnimatedContainer(
                                duration: Motion.short,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isYouTubeMode
                                      ? colorScheme.primaryContainer
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      FluentIcons.globe_20_filled,
                                      size: 20,
                                      color: isYouTubeMode
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'YouTube',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: isYouTubeMode
                                              ? colorScheme.onPrimaryContainer
                                              : colorScheme.onSurfaceVariant,
                                          fontWeight: isYouTubeMode
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: ClickDetector(
                              onTap: () {
                                dialogSetState(() {
                                  isYouTubeMode = false;
                                  id = '';
                                  customPlaylistName = '';
                                  imageUrl = null;
                                  imageBase64 = null;
                                });
                              },
                              child: AnimatedContainer(
                                duration: Motion.short,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: !isYouTubeMode
                                      ? colorScheme.primaryContainer
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      FluentIcons.person_20_filled,
                                      size: 20,
                                      color: !isYouTubeMode
                                          ? colorScheme.onPrimaryContainer
                                          : colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        context.l10n!.custom,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: !isYouTubeMode
                                              ? colorScheme.onPrimaryContainer
                                              : colorScheme.onSurfaceVariant,
                                          fontWeight: !isYouTubeMode
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 20),
                  if (isYouTubeMode)
                    TextField(
                      key: const ValueKey('youtube-playlist-link'),
                      decoration: InputDecoration(
                        labelText: context.l10n!.youtubePlaylistLinkOrId,
                        prefixIcon: Icon(
                          FluentIcons.link_20_regular,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerLow,
                      ),
                      onChanged: (value) {
                        id = value;
                      },
                    )
                  else ...[
                    TextField(
                      key: const ValueKey('custom-playlist-name'),
                      decoration: InputDecoration(
                        labelText: context.l10n!.customPlaylistName,
                        prefixIcon: Icon(
                          FluentIcons.text_field_20_regular,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: colorScheme.surfaceContainerLow,
                      ),
                      autofocus: true,
                      onChanged: (value) {
                        customPlaylistName = value;
                      },
                    ),
                    if (imageBase64 == null) ...[
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          labelText: context.l10n!.customPlaylistImgUrl,
                          prefixIcon: Icon(
                            FluentIcons.image_20_regular,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerLow,
                        ),
                        onChanged: (value) {
                          imageUrl = value;
                          imageBase64 = null;
                          dialogSetState(() {});
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (imageUrl == null) ...[
                      buildImagePickerRow(
                        context,
                        _pickImage,
                        imageBase64 != null,
                      ),
                      _imagePreview(),
                    ],
                  ],
                ],
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: <Widget>[
              const DialogCancel(style: DialogCancelStyle.outlined),
              FilledButton.icon(
                onPressed: () async {
                  if (isYouTubeMode && id.isNotEmpty) {
                    final result = await addUserPlaylist(id, context);
                    if (context.mounted) showToast(context, result);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  } else if (!isYouTubeMode &&
                      customPlaylistName.trim().isNotEmpty) {
                    final (result, newPlaylistId) = createCustomPlaylist(
                      customPlaylistName.trim(),
                      imageBase64 ?? imageUrl,
                      context,
                    );
                    if (songToAdd != null) {
                      if (context.mounted) {
                        final addResult = addSongInCustomPlaylist(
                          context,
                          newPlaylistId,
                          songToAdd,
                        );
                        showToast(context, addResult);
                      }
                    } else if (songsToAdd != null && songsToAdd.isNotEmpty) {
                      if (context.mounted) {
                        final addResult = addSongsInCustomPlaylist(
                          context,
                          newPlaylistId,
                          songsToAdd,
                        );
                        showToast(context, addResult);
                      }
                    } else {
                      if (context.mounted) showToast(context, result);
                    }
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  } else {
                    showToast(
                      context,
                      '${context.l10n!.provideIdOrNameError}.',
                    );
                  }
                },
                icon: const Icon(FluentIcons.add_20_filled),
                label: Text(context.l10n!.add),
              ),
            ],
          );
        },
      );
    },
  );
}

/// [song] when it can be liked: a song with an id that is not a local file.
Map? _likableSong(dynamic song) {
  if (song is! Map) return null;
  final ytid = song['ytid']?.toString() ?? '';
  return ytid.isEmpty || isLocalSongId(ytid) ? null : song;
}

/// The dialog to put [song], or [songs], in a playlist. A single song also
/// gets the liked songs at the top, as a playlist that stands out, and one
/// tap likes it or takes the like back. In the same way, one tap on a playlist
/// puts the song in it or, if it is there, takes it out.
void showAddToPlaylistDialog(
  BuildContext context, {
  dynamic song,
  List<dynamic>? songs,
}) {
  final likableSong = _likableSong(song);
  showDialog(
    context: context,
    builder: (BuildContext context) {
      final colorScheme = Theme.of(context).colorScheme;
      return AlertDialog(
        icon: const DialogIconHeader(
          icon: FluentIcons.album_add_24_filled,
          secondary: true,
        ),
        title: Text(
          context.l10n!.addToPlaylist,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        content: Container(
          width: double.maxFinite,
          constraints: BoxConstraints(
            maxHeight: math.min(440, MediaQuery.sizeOf(context).height * 0.6),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (likableSong != null) _LikedSongsItem(song: likableSong),
              Flexible(
                child: Builder(
                  builder: (context) {
                    final folders = userPlaylistFolders.value
                        .where(
                          (folder) =>
                              folder['playlists'] != null &&
                              (folder['playlists'] as List).isNotEmpty,
                        )
                        .toList();
                    final topLevelPlaylists = getPlaylistsNotInFolders();

                    final hasAny =
                        (folders.isNotEmpty) || (topLevelPlaylists.isNotEmpty);

                    if (!hasAny) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32),
                            child: Text(
                              context.l10n!.noCustomPlaylists,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      );
                    }

                    return ListView.builder(
                      itemCount: folders.length + topLevelPlaylists.length,
                      shrinkWrap: true,
                      itemBuilder: (context, index) {
                        if (index < folders.length) {
                          final folder = folders[index];

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: ExpansionTile(
                              collapsedBackgroundColor:
                                  colorScheme.surfaceContainerLow,
                              backgroundColor:
                                  colorScheme.surfaceContainerLowest,
                              shape: const RoundedRectangleBorder(
                                borderRadius: commonCustomBarRadius,
                              ),
                              collapsedShape: const RoundedRectangleBorder(
                                borderRadius: commonCustomBarRadius,
                              ),
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              leading: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  FluentIcons.folder_24_regular,
                                  color: colorScheme.secondary,
                                  size: 22,
                                ),
                              ),
                              title: Text(
                                folder['name'] ?? '',
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              children: [
                                for (final p
                                    in (folder['playlists'] as List? ?? []))
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      left: 16,
                                      right: 16,
                                    ),
                                    child: _PlaylistItem(
                                      playlist: p,
                                      song: song,
                                      songs: songs,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }

                        final playlistIndex = index - folders.length;
                        final playlist = topLevelPlaylists[playlistIndex];

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: _PlaylistItem(
                            playlist: playlist,
                            song: song,
                            songs: songs,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actions: [
          const DialogCancel(),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              showCreatePlaylistDialog(
                context,
                songToAdd: song,
                songsToAdd: songs,
              );
            },
            icon: const Icon(FluentIcons.add_24_regular, size: 18),
            label: Text(context.l10n!.addPlaylist),
          ),
        ],
      );
    },
  );
}

/// The liked songs among the playlists: a row that stands out from them, which
/// likes the song or, if it is liked, takes the like back.
class _LikedSongsItem extends StatelessWidget {
  const _LikedSongsItem({required this.song});

  final Map song;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n!;
    final ytid = song['ytid'].toString();
    return ValueListenableBuilder<List>(
      valueListenable: userLikedSongsList,
      builder: (context, _, _) {
        final liked = isSongAlreadyLiked(ytid);
        return DialogItem(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
          icon: FluentIcons.heart_24_filled,
          iconColor: colorScheme.onPrimary,
          iconBgColor: colorScheme.primary,
          backgroundColor: colorScheme.primaryContainer,
          label: l10n.likedSongs,
          trailing: _InListMark(inList: liked),
          onTap: () {
            showToast(
              context,
              liked ? l10n.removedFromLikedSongs : l10n.addedToLikedSongs,
              duration: const Duration(seconds: 1),
            );
            Navigator.pop(context);
            updateSongLikeStatus(ytid, !liked, songData: song);
          },
        );
      },
    );
  }
}

/// A playlist the song can go in. With one song, it also says whether the song
/// is already in it, and the same tap takes it out (as the liked songs do);
/// with many, it has the chevron of a row that opens.
class _PlaylistItem extends StatelessWidget {
  const _PlaylistItem({required this.playlist, this.song, this.songs});

  final Map playlist;
  final dynamic song;
  final List<dynamic>? songs;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ytid = song is Map ? songYtid(song as Map) : null;
    // The song as the playlist holds it, when it does.
    final held = ytid != null && playlist['list'] is List
        ? findSongByYtid(playlist['list'] as List, ytid)
        : null;
    return DialogItem(
      icon: FluentIcons.text_bullet_list_24_filled,
      iconColor: colorScheme.tertiary,
      iconBgColor: colorScheme.tertiaryContainer,
      label: playlist['title'] ?? '',
      trailing: ytid == null ? null : _InListMark(inList: held != null),
      onTap: () {
        if (held != null) {
          final l10n = context.l10n!;
          showToast(
            context,
            removeSongFromPlaylist(playlist, held)
                ? l10n.songRemoved
                : l10n.error,
          );
        } else if (song != null) {
          showToast(
            context,
            addSongInCustomPlaylist(context, playlist['ytid'], song),
          );
        } else if (songs != null && songs!.isNotEmpty) {
          showToast(
            context,
            addSongsInCustomPlaylist(context, playlist['ytid'], songs!),
          );
        }
        Navigator.pop(context);
      },
    );
  }
}

/// At the end of a row of the dialog: a check when the song is in it, a plus
/// when it is not.
class _InListMark extends StatelessWidget {
  const _InListMark({required this.inList});

  final bool inList;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Icon(
      inList
          ? FluentIcons.checkmark_circle_24_filled
          : FluentIcons.add_circle_24_regular,
      color: inList ? colorScheme.primary : colorScheme.onSurfaceVariant,
      size: 24,
    );
  }
}
