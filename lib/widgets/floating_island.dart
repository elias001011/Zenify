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
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/screens/search_page.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/floating_surface.dart';

const double _islandHeight = 44;
const double _islandMargin = 10;

/// A page with the floating island in place of an app bar: back (when there
/// is somewhere to go back to), the page title and optional actions.
///
/// The body extends under the island and gets its height as top padding,
/// which scroll views read like the bottom padding of the floating dock.
class IslandScaffold extends StatefulWidget {
  const IslandScaffold({
    super.key,
    required this.title,
    required this.body,
    this.fadeTitleAfter,
    this.actions = const [],
    this.onBack,
    this.onFilter,
    this.globalSearch = true,
  });

  final String title;
  final Widget body;

  /// Turns the search shortcut into a live filter of this page (playlists).
  final ValueChanged<String>? onFilter;

  /// Offer the search shortcut, which opens the search page on Enter.
  final bool globalSearch;

  /// Scroll offset after which the title fades in, for pages that show their
  /// own big title (playlists) until it scrolls under the island.
  final double? fadeTitleAfter;
  final List<Widget> actions;

  /// Replaces the default pop, e.g. to return a result.
  final VoidCallback? onBack;

  /// Space a page keeps free at the top for the island.
  static const double inset = _islandHeight + _islandMargin * 2;

  @override
  State<IslandScaffold> createState() => _IslandScaffoldState();
}

class _IslandScaffoldState extends State<IslandScaffold> {
  static const _fadeDistance = 32.0;

  late final _titleOpacity = ValueNotifier<double>(
    widget.fadeTitleAfter == null ? 1 : 0,
  );

  @override
  void dispose() {
    _titleOpacity.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollUpdateNotification notification) {
    final start = widget.fadeTitleAfter;
    if (start != null &&
        notification.depth == 0 &&
        notification.metrics.axis == Axis.vertical) {
      _titleOpacity.value =
          ((notification.metrics.pixels - start) / _fadeDistance).clamp(
            0.0,
            1.0,
          );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Scaffold(
      body: Stack(
        children: [
          NotificationListener<ScrollUpdateNotification>(
            onNotification: _onScroll,
            child: MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(
                  top: media.padding.top + IslandScaffold.inset,
                ),
              ),
              child: widget.body,
            ),
          ),
          Positioned(
            top: media.padding.top + _islandMargin,
            left: _islandMargin,
            child: _Island(
              title: widget.title,
              titleOpacity: widget.fadeTitleAfter == null
                  ? null
                  : _titleOpacity,
              actions: widget.actions,
              onBack: widget.onBack,
              onFilter: widget.onFilter,
              globalSearch: widget.globalSearch,
              maxWidth: media.size.width - _islandMargin * 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _Island extends StatefulWidget {
  const _Island({
    required this.title,
    required this.titleOpacity,
    required this.actions,
    required this.onBack,
    required this.onFilter,
    required this.globalSearch,
    required this.maxWidth,
  });

  final String title;
  final ValueListenable<double>? titleOpacity;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final ValueChanged<String>? onFilter;
  final bool globalSearch;
  final double maxWidth;

  @override
  State<_Island> createState() => _IslandState();
}

class _IslandState extends State<_Island> {
  static const _searchWidth = 480.0;

  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _controller.clear();
    widget.onFilter?.call('');
    setState(() => _searching = false);
  }

  void _submit(String query) {
    if (widget.onFilter != null) {
      _focusNode.unfocus();
      return;
    }
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _closeSearch();
    openSearch(trimmed);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _closeSearch();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final showSearch =
        widget.onFilter != null || (widget.globalSearch && !offlineMode.value);
    final width = _searching
        ? (widget.maxWidth < _searchWidth ? widget.maxWidth : _searchWidth)
        : null;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: FloatingSurface(
        borderRadius: const BorderRadius.all(
          Radius.circular(_islandHeight / 2),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.centerLeft,
          child: SizedBox(
            height: _islandHeight,
            width: width,
            child: _searching
                ? _buildSearchField(context)
                : _buildBar(context, showSearch),
          ),
        ),
      ),
    );
  }

  Widget _buildBar(BuildContext context, bool showSearch) {
    final colorScheme = Theme.of(context).colorScheme;
    final canPop = Navigator.of(context).canPop();

    Widget titleText = Padding(
      padding: EdgeInsets.only(left: canPop ? 2 : 14, right: 10),
      child: Text(
        widget.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // The logo font sits low in its line box; even leading centres it.
        style: TextStyle(
          fontSize: 18,
          height: 1,
          leadingDistribution: TextLeadingDistribution.even,
          fontFamily: 'paytoneOne',
          color: colorScheme.primary,
        ),
      ),
    );
    if (widget.titleOpacity != null) {
      titleText = ValueListenableBuilder<double>(
        valueListenable: widget.titleOpacity!,
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity.clamp(0.0, 1.0), child: child),
        child: titleText,
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (canPop)
          IconButton(
            icon: const Icon(FluentIcons.arrow_left_24_regular),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
          ),
        if (widget.title.isNotEmpty) Flexible(child: titleText),
        ...widget.actions,
        if (showSearch)
          IconButton(
            icon: const Icon(FluentIcons.search_24_regular),
            tooltip: context.l10n!.search,
            onPressed: _openSearch,
          ),
        const SizedBox(width: 2),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        const SizedBox(width: 14),
        Icon(
          FluentIcons.search_24_regular,
          size: 20,
          color: colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Focus(
            onKeyEvent: _onKey,
            canRequestFocus: false,
            skipTraversal: true,
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textInputAction: TextInputAction.search,
              onChanged: widget.onFilter,
              onSubmitted: _submit,
              style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: context.l10n!.search,
                filled: false,
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ),
        IconButton(
          icon: const Icon(FluentIcons.dismiss_24_regular),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: _closeSearch,
        ),
        const SizedBox(width: 2),
      ],
    );
  }
}

/// [padding] plus the island's space, for scroll views that do not read the
/// top padding themselves (e.g. [SingleChildScrollView]). The shell already
/// takes the system inset, so the island's own height is all that is added.
EdgeInsets withIslandInset(BuildContext context, EdgeInsets padding) =>
    padding.copyWith(top: padding.top + IslandScaffold.inset);

/// The island's space as the first sliver of a [CustomScrollView].
class SliverIslandTopSpace extends StatelessWidget {
  const SliverIslandTopSpace({super.key});

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SizedBox(height: MediaQuery.paddingOf(context).top),
  );
}
