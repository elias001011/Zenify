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
class LocalFilesPage extends StatefulWidget {
  const LocalFilesPage({super.key});

  @override
  State<LocalFilesPage> createState() => _LocalFilesPageState();
}

class _LocalFilesPageState extends State<LocalFilesPage> {
  /// What the island's search shortcut filters the songs by, lowercase.
  String _query = '';

  bool _matches(Map file) =>
      _query.isEmpty ||
      '${file['title']} ${file['artist']}'.toLowerCase().contains(_query);

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
    final padding = readableInset(context, commonSingleChildScrollViewPadding);
    return IslandScaffold(
      title: l10n.localFiles,
      onFilter: (value) => setState(() => _query = value.trim().toLowerCase()),
      actions: [
        IconButton(
          icon: const Icon(FluentIcons.add_24_regular),
          tooltip: l10n.addLocalFiles,
          onPressed: () => _addFiles(context),
        ),
      ],
      body: ValueListenableBuilder<List<Map>>(
        valueListenable: localFiles,
        builder: (context, files, _) {
          final shown = [
            for (final file in files)
              if (_matches(file)) file,
          ];
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: padding,
                sliver: shown.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            files.isEmpty
                                ? l10n.localFilesEmpty
                                : l10n.noLibraryMatches,
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
                        itemCount: shown.length,
                        itemBuilder: (context, i) => CustomBar(
                          key: ValueKey(shown[i]['ytid']),
                          shown[i]['title']?.toString() ?? '',
                          FluentIcons.music_note_2_24_regular,
                          borderRadius: getItemBorderRadius(i, shown.length),
                          // The whole list keeps playing, from the song
                          // picked, whatever the filter hides.
                          onTap: () => audioHandler.playPlaylistSong(
                            playlist: {'list': List<Map>.of(files)},
                            songIndex: files.indexOf(shown[i]),
                          ),
                          trailing: IconButton(
                            icon: const Icon(FluentIcons.delete_24_regular),
                            tooltip: l10n.removeLocalFile,
                            onPressed: () =>
                                removeLocalFile(shown[i]['ytid'].toString()),
                          ),
                        ),
                      ),
              ),
              const SliverMiniPlayerBottomSpace(),
            ],
          );
        },
      ),
    );
  }
}
