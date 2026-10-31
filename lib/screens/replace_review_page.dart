/*
 *     Copyright (C) 2025 Valeri Gokadze
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
import 'package:musify/services/song_replacement.dart';
import 'package:musify/services/unavailable_songs.dart';
import 'package:musify/widgets/floating_island.dart';
import 'package:musify/widgets/mini_player_bottom_space.dart';
import 'package:musify/widgets/song_bar.dart';

/// The unavailable songs of a [ReplacementPlan] beside what would replace
/// them, to read, play and change before anything is swapped. Pops the swaps
/// to make (the ytid to leave and the song to take its place), or null when
/// the person backs out.
class ReplaceReviewPage extends StatefulWidget {
  const ReplaceReviewPage({
    super.key,
    required this.plan,
    this.search = searchReplacementCandidates,
  });

  final ReplacementPlan plan;

  /// Where the manual search looks; tests give their own.
  final Future<List<Map>> Function(String query) search;

  @override
  State<ReplaceReviewPage> createState() => _ReplaceReviewPageState();
}

class _ReplaceReviewPageState extends State<ReplaceReviewPage> {
  late final _chosen = Map<String, Map>.of(widget.plan.found);
  final _byYou = <String>{};
  final _skipped = <String>{};

  Future<void> _searchManually(Map song) async {
    final id = song['ytid'].toString();
    final exclude = {
      ...widget.plan.held,
      for (final entry in _chosen.entries)
        if (entry.key != id) entry.value['ytid'].toString(),
    };
    final picked = await showModalBottomSheet<Map>(
      context: context,
      isScrollControlled: true,
      builder: (context) =>
          _ManualSearch(song: song, search: widget.search, exclude: exclude),
    );
    if (picked == null) return;
    setState(() {
      _chosen[id] = picked;
      _byYou.add(id);
    });
  }

  // What is shown under a song that has no replacement.
  String _missing(AppLocalizations l10n, String id) =>
      widget.plan.notSearched.contains(id)
      ? l10n.replaceSearchFailed
      : _skipped.contains(id)
      ? l10n.replaceNotReplaced
      : l10n.noReplacementFound;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    final colors = Theme.of(context).colorScheme;
    return IslandScaffold(
      title: l10n.replaceReviewTitle,
      globalSearch: false,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                const SliverIslandTopSpace(),
                SliverPadding(
                  padding: commonSingleChildScrollViewPadding,
                  sliver: SliverList.separated(
                    itemCount: widget.plan.songs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final song = widget.plan.songs[index];
                      final chosen = _chosen[song['ytid'].toString()];
                      return DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _Label(l10n.replaceReviewOld),
                              SongBar(song, true),
                              const SizedBox(height: 8),
                              _Label(
                                _byYou.contains(song['ytid'].toString())
                                    ? l10n.replaceChosenByYou
                                    : l10n.replaceReviewNew,
                              ),
                              if (chosen != null)
                                SongBar(chosen, true)
                              else
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Text(
                                    _missing(l10n, song['ytid'].toString()),
                                    style: TextStyle(color: colors.error),
                                  ),
                                ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Wrap(
                                  children: [
                                    if (chosen != null)
                                      TextButton(
                                        onPressed: () => setState(() {
                                          final id = song['ytid'].toString();
                                          _chosen.remove(id);
                                          _byYou.remove(id);
                                          _skipped.add(id);
                                        }),
                                        child: Text(l10n.replaceKeepAsIs),
                                      ),
                                    TextButton.icon(
                                      onPressed: () => _searchManually(song),
                                      icon: const Icon(
                                        FluentIcons.search_24_regular,
                                      ),
                                      label: Text(l10n.replaceSearchManually),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _chosen.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_chosen),
                  child: Text(l10n.replaceSwapAction(_chosen.length)),
                ),
              ],
            ),
          ),
          const MiniPlayerBottomSpace(),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

/// A search to pick a replacement from; pops the chosen song.
class _ManualSearch extends StatefulWidget {
  const _ManualSearch({
    required this.song,
    required this.search,
    required this.exclude,
  });

  final Map song;
  final Future<List<Map>> Function(String query) search;

  /// Songs that are no replacement: those the playlists hold, those chosen.
  final Set<String> exclude;

  @override
  State<_ManualSearch> createState() => _ManualSearchState();
}

class _ManualSearchState extends State<_ManualSearch> {
  late final _query = TextEditingController(
    text: replacementQuery(widget.song),
  );
  List<Map> _results = [];
  var _searching = false;
  var _searches = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final search = ++_searches;
    setState(() => _searching = true);
    final results = await widget.search(_query.text.trim());
    // A newer search is under way: its answer is the one to show.
    if (!mounted || search != _searches) return;
    setState(() {
      _results = [
        for (final result in results)
          if (!widget.exclude.contains(result['ytid'].toString()) &&
              !unavailableSongs.contains(result['ytid']))
            result,
      ];
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _query,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _run(),
              decoration: InputDecoration(
                hintText: context.l10n!.replaceManualHint,
                suffixIcon: IconButton(
                  icon: const Icon(FluentIcons.search_24_regular),
                  onPressed: _run,
                ),
              ),
            ),
          ),
          if (_searching) const LinearProgressIndicator(),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) => SongBar(
                _results[index],
                true,
                trailing: IconButton(
                  icon: const Icon(FluentIcons.checkmark_24_regular),
                  onPressed: () => Navigator.of(context).pop(_results[index]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
