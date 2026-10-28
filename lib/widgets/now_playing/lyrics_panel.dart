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
import 'package:musify/services/common_services.dart';
import 'package:musify/services/lyrics/lyrics_models.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/async_loader.dart';
import 'package:musify/widgets/now_playing/synced_lyrics_view.dart';

/// The current song's lyrics, synced when available. Fetched lazily per
/// song.
class LyricsPanel extends StatefulWidget {
  const LyricsPanel({super.key, required this.metadata});
  final MediaItem metadata;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  String? _resolvedKey;
  late Future<Lyrics?> _lyricsFuture;

  @override
  void initState() {
    super.initState();
    _resolveIfNeeded();
  }

  @override
  void didUpdateWidget(LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolveIfNeeded();
  }

  void _resolveIfNeeded() {
    final key = '${widget.metadata.artist} - ${widget.metadata.title}';
    if (key == _resolvedKey) return;
    _resolvedKey = key;
    _lyricsFuture = getSongLyricsResult(
      widget.metadata.artist,
      widget.metadata.title,
      duration: widget.metadata.duration,
      album: widget.metadata.album,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget unavailable() => Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.text_quote_24_regular,
            size: 48,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            context.l10n!.lyricsNotAvailable,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    return AsyncLoader<Lyrics?>(
      future: _lyricsFuture,
      emptyWidget: unavailable(),
      errorBuilder: (ctx, error, stack) => unavailable(),
      builder: (context, lyrics) {
        if (lyrics == null || lyrics.isEmpty) return unavailable();

        // Re-evaluated when the setting changes, so toggling it takes effect
        // without reloading the lyrics.
        return ValueListenableBuilder<bool>(
          valueListenable: syncedLyricsEnabled,
          builder: (context, syncedEnabled, _) {
            if (lyrics.isSynced && syncedEnabled) {
              return SyncedLyricsView(lyrics: lyrics);
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              physics: const BouncingScrollPhysics(),
              child: Text(
                formatPlainLyrics(lyrics),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
            );
          },
        );
      },
    );
  }
}
