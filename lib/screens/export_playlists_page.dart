import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/services/playlist_export_service.dart';
import 'package:musify/utilities/app_utils.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/platform_utils.dart';
import 'package:musify/widgets/custom_bar.dart';
import 'package:musify/widgets/floating_island.dart';
import 'package:musify/widgets/mini_player.dart';
import 'package:share_plus/share_plus.dart';

/// Saves the playlists the user picks as CSV files, the format the Spotify
/// import reads. Online only: playlists added from YouTube are loaded from it.
class ExportPlaylistsPage extends StatefulWidget {
  const ExportPlaylistsPage({super.key});

  @override
  State<ExportPlaylistsPage> createState() => _ExportPlaylistsPageState();
}

class _ExportPlaylistsPageState extends State<ExportPlaylistsPage> {
  List<ExportEntry>? _entries;
  final _selected = <String>{};
  bool _exporting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _entries ?? _load();
  }

  Future<void> _load() async {
    final entries = await exportableLibrary(
      likedSongsTitle: context.l10n!.likedSongs,
    );
    if (mounted) setState(() => _entries = entries);
  }

  IconData _icon(ExportSource source) => switch (source) {
    ExportSource.likedSongs => FluentIcons.heart_24_regular,
    ExportSource.custom => FluentIcons.music_note_2_24_regular,
    ExportSource.youtube => FluentIcons.video_clip_24_regular,
    ExportSource.saved => FluentIcons.library_24_regular,
    ExportSource.zenify => FluentIcons.bookmark_24_regular,
  };

  void _toggle(ExportEntry entry) => setState(() {
    if (!_selected.remove(entry.id)) _selected.add(entry.id);
  });

  void _toggleAll(List<ExportEntry> entries) => setState(() {
    final all = _selected.length == entries.length;
    _selected.clear();
    if (!all) _selected.addAll(entries.map((entry) => entry.id));
  });

  Future<void> _export() async {
    final chosen = [
      for (final entry in _entries ?? const <ExportEntry>[])
        if (_selected.contains(entry.id)) entry,
    ];
    if (chosen.isEmpty || _exporting) return;
    setState(() => _exporting = true);
    Directory? temporary;
    try {
      // A phone has no folder to write to: the files go through the share
      // sheet, where they can be saved or sent.
      final Directory? target;
      if (isDesktopPlatform) {
        final picked = await FilePicker.getDirectoryPath(
          dialogTitle: context.l10n!.exportPlaylistsCsv,
        );
        target = picked == null ? null : Directory(picked);
      } else {
        temporary = await Directory.systemTemp.createTemp('zenify_export');
        target = temporary;
      }
      if (target == null) return;

      final result = await writePlaylistCsvs(chosen, target);
      if (!mounted) return;
      if (result.files.isEmpty) {
        showToast(context, context.l10n!.exportPlaylistsNone);
        return;
      }
      if (!isDesktopPlatform) {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              for (final path in result.files)
                XFile(path, mimeType: 'text/csv'),
            ],
          ),
        );
      }
      if (!mounted) return;
      showToast(
        context,
        result.failed == 0
            ? context.l10n!.exportPlaylistsDone(result.files.length)
            : context.l10n!.exportPlaylistsPartial(
                result.files.length,
                result.failed,
              ),
      );
    } catch (e, stackTrace) {
      logger.log('Error exporting playlists', error: e, stackTrace: stackTrace);
      if (mounted) showToast(context, context.l10n!.error);
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final allSelected =
        entries != null &&
        entries.isNotEmpty &&
        _selected.length == entries.length;
    return IslandScaffold(
      title: context.l10n!.exportPlaylistsCsv,
      body: ReadablePadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        builder: (context, padding) => SingleChildScrollView(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.l10n!.exportPlaylistsInstructions),
              const SizedBox(height: 16),
              if (entries == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (entries.isEmpty)
                Text(context.l10n!.exportPlaylistsEmpty)
              else ...[
                CustomBar(
                  context.l10n!.selectAll,
                  FluentIcons.checkmark_circle_24_regular,
                  borderRadius: commonCustomBarRadius,
                  trailing: Checkbox(
                    value: allSelected,
                    onChanged: _exporting ? null : (_) => _toggleAll(entries),
                  ),
                  onTap: _exporting ? null : () => _toggleAll(entries),
                ),
                const SizedBox(height: 12),
                for (final (index, entry) in entries.indexed)
                  CustomBar(
                    entry.title,
                    _icon(entry.source),
                    borderRadius: getItemBorderRadius(index, entries.length),
                    trailing: Checkbox(
                      value: _selected.contains(entry.id),
                      onChanged: _exporting ? null : (_) => _toggle(entry),
                    ),
                    onTap: _exporting ? null : () => _toggle(entry),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _exporting || _selected.isEmpty ? null : _export,
                  icon: _exporting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(FluentIcons.arrow_download_24_regular),
                  label: Text(context.l10n!.exportPlaylists),
                ),
              ],
              const SizedBox(height: MiniPlayer.playerHeight + 24),
            ],
          ),
        ),
      ),
    );
  }
}
