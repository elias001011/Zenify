import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/services/local_files_service.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/widgets/custom_bar.dart';
import 'package:musify/widgets/floating_island.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';

/// Audio files from this device, played here and nowhere else: they are not
/// downloaded, liked, put in playlists, counted in the recap or synced.
class LocalFilesPage extends StatelessWidget {
  const LocalFilesPage({super.key});

  Future<void> _addFiles(BuildContext context) async {
    final picked = await FilePicker.pickFiles(type: FileType.audio);
    final paths = [
      for (final file in picked)
        if (file.path != null) file.path!,
    ];
    if (paths.isEmpty) return;
    final result = await addLocalFiles(paths);
    if (!context.mounted) return;
    showToast(
      context,
      context.l10n!.localFilesImportResult(result.added, result.failed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    return IslandScaffold(
      title: l10n.localFiles,
      globalSearch: false,
      actions: [
        IconButton(
          icon: const Icon(FluentIcons.add_24_regular),
          tooltip: l10n.addLocalFiles,
          onPressed: () => _addFiles(context),
        ),
      ],
      body: ReadablePadding(
        padding: commonSingleChildScrollViewPadding,
        builder: (context, padding) => ValueListenableBuilder<List<Map>>(
          valueListenable: localFiles,
          builder: (context, files, _) => CustomScrollView(
            slivers: [
              SliverPadding(
                padding: padding,
                sliver: files.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            l10n.localFilesEmpty,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : SliverList.builder(
                        itemCount: files.length,
                        itemBuilder: (context, i) => CustomBar(
                          key: ValueKey(files[i]['ytid']),
                          files[i]['title']?.toString() ?? '',
                          FluentIcons.music_note_2_24_regular,
                          borderRadius: getItemBorderRadius(i, files.length),
                          onTap: () => audioHandler.playPlaylistSong(
                            playlist: {'list': List<Map>.of(files)},
                            songIndex: i,
                          ),
                          trailing: IconButton(
                            icon: const Icon(FluentIcons.delete_24_regular),
                            tooltip: l10n.removeLocalFile,
                            onPressed: () =>
                                removeLocalFile(files[i]['ytid'].toString()),
                          ),
                        ),
                      ),
              ),
              const SliverMiniPlayerBottomSpace(),
            ],
          ),
        ),
      ),
    );
  }
}
