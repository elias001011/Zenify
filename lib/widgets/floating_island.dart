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
const double _islandMargin = FloatingSurface.edgeMargin;

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
    this.headerTitleKey,
    this.actions = const [],
    this.onBack,
    this.onFilter,
    this.globalSearch = true,
    this.background,
  });

  final String title;
  final Widget body;

  /// Behind the body and the island, e.g. the page glow; it does not scroll.
  final Widget? background;

  /// Turns the search shortcut into a live filter of this page (playlists).
  final ValueChanged<String>? onFilter;

  /// Offer the search shortcut, which opens the search page on Enter.
  final bool globalSearch;

  /// Scroll offset after which the title appears, for pages that show their
  /// own big title (playlists). Until then the island stays compact.
  final double? fadeTitleAfter;

  /// The title in the scrolling header. Show the island title only once its
  /// bottom has left the visible page, including wrapped and scaled text.
  final GlobalKey? headerTitleKey;
  final List<Widget> actions;

  /// Replaces the default pop, e.g. to return a result.
  final VoidCallback? onBack;

  /// Space a page keeps free at the top for the island.
  static const double inset = _islandHeight + _islandMargin * 2;

  /// Space a page keeps free at the top: the status bar, which its background
  /// reaches under, and the island. The same wherever it is read on the page,
  /// since it comes from the view padding, which the scaffold leaves alone.
  static double topSpace(BuildContext context) =>
      MediaQuery.viewPaddingOf(context).top + inset;

  @override
  State<IslandScaffold> createState() => _IslandScaffoldState();
}

class _IslandScaffoldState extends State<IslandScaffold> {
  late final _titleShown = ValueNotifier<bool>(
    widget.fadeTitleAfter == null && widget.headerTitleKey == null,
  );
  bool _visibilityScheduled = false;

  void _scheduleTitleVisibility() {
    if (widget.headerTitleKey == null || _visibilityScheduled) return;
    _visibilityScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityScheduled = false;
      if (!mounted) return;
      final title = widget.headerTitleKey?.currentContext?.findRenderObject();
      final page = context.findRenderObject();
      if (title is RenderBox && title.hasSize && page is RenderBox) {
        final bottom = title
            .localToGlobal(Offset(0, title.size.height), ancestor: page)
            .dy;
        _titleShown.value = bottom <= MediaQuery.viewPaddingOf(context).top;
      }
    });
  }

  @override
  void didUpdateWidget(IslandScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.headerTitleKey != oldWidget.headerTitleKey ||
        widget.fadeTitleAfter != oldWidget.fadeTitleAfter) {
      _titleShown.value =
          widget.headerTitleKey == null && widget.fadeTitleAfter == null;
    }
  }

  @override
  void dispose() {
    _titleShown.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollUpdateNotification notification) {
    if (widget.headerTitleKey != null) {
      if (notification.depth == 0 &&
          notification.metrics.axis == Axis.vertical) {
        _scheduleTitleVisibility();
      }
      return false;
    }
    final start = widget.fadeTitleAfter;
    if (start != null &&
        notification.depth == 0 &&
        notification.metrics.axis == Axis.vertical) {
      _titleShown.value = notification.metrics.pixels > start;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    _scheduleTitleVisibility();
    final media = MediaQuery.of(context);
    // Room for the desktop rail, which floats over the page's background.
    final left = media.padding.left;

    return Scaffold(
      body: Stack(
        children: [
          if (widget.background case final background?)
            Positioned.fill(child: IgnorePointer(child: background)),
          NotificationListener<ScrollUpdateNotification>(
            onNotification: _onScroll,
            child: Padding(
              padding: EdgeInsets.only(left: left),
              child: MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(
                    top: IslandScaffold.topSpace(context),
                    left: 0,
                  ),
                ),
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: (_) {
                    _scheduleTitleVisibility();
                    return false;
                  },
                  child: widget.body,
                ),
              ),
            ),
          ),
          Positioned(
            top: media.viewPadding.top + _islandMargin,
            left: left + _islandMargin,
            child: _Island(
              title: widget.title,
              titleShown: _titleShown,
              actions: widget.actions,
              onBack: widget.onBack,
              onFilter: widget.onFilter,
              globalSearch: widget.globalSearch,
              maxWidth: media.size.width - left - _islandMargin * 2,
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
    required this.titleShown,
    required this.actions,
    required this.onBack,
    required this.onFilter,
    required this.globalSearch,
    required this.maxWidth,
  });

  final String title;
  final ValueListenable<bool> titleShown;
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
    offlineMode.removeListener(_onOfflineChanged);
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
    if (trimmed.isEmpty || offlineMode.value) return;
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
  void initState() {
    super.initState();
    offlineMode.addListener(_onOfflineChanged);
  }

  void _onOfflineChanged() {
    // Global search needs the network; a playlist filter does not.
    if (offlineMode.value && _searching && widget.onFilter == null) {
      _closeSearch();
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final showSearch =
        widget.onFilter != null || (widget.globalSearch && !offlineMode.value);
    final width = _searching
        ? (widget.maxWidth < _searchWidth ? widget.maxWidth : _searchWidth)
        : null;

    // Its own layer: with blur on, resizing would repaint the page each frame.
    return RepaintBoundary(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: FloatingSurface(
          borderRadius: const BorderRadius.all(
            Radius.circular(_islandHeight / 2),
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.fastOutSlowIn,
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
      ),
    );
  }

  Widget _buildBar(BuildContext context, bool showSearch) {
    final colorScheme = Theme.of(context).colorScheme;
    // Only pages pushed over another one in their own navigator: a tab's
    // first page has nowhere to go back to.
    final canPop = !(ModalRoute.of(context)?.isFirst ?? true);

    final titleText = Padding(
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
    return ValueListenableBuilder<bool>(
      valueListenable: widget.titleShown,
      builder: (context, titleShown, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canPop)
            IconButton(
              icon: const Icon(FluentIcons.arrow_left_24_regular),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed:
                  widget.onBack ?? () => Navigator.of(context).maybePop(),
            ),
          // Left out while hidden, so the island stays compact.
          if (widget.title.isNotEmpty && titleShown)
            Flexible(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 220),
                builder: (context, opacity, child) =>
                    Opacity(opacity: opacity, child: child),
                child: titleText,
              ),
            ),
          ...widget.actions,
          if (showSearch)
            IconButton(
              icon: const Icon(FluentIcons.search_24_regular),
              tooltip: context.l10n!.search,
              onPressed: _openSearch,
            ),
          const SizedBox(width: 2),
        ],
      ),
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

/// [padding] plus [IslandScaffold.topSpace], for scroll views that do not
/// read the top padding themselves (e.g. [SingleChildScrollView]).
EdgeInsets withIslandInset(BuildContext context, EdgeInsets padding) =>
    padding.copyWith(top: padding.top + IslandScaffold.topSpace(context));

/// Settings and other pages of controls and text keep to this width on wide
/// windows, centred, as desktop players do; music lists use the whole window.
const double readableWidth = 860;

/// Builds a page's scroll view with [padding], the island's space on top and
/// whatever room either side centres the content within [readableWidth]. The
/// margins stay part of the scroll view, so it scrolls from anywhere and its
/// scrollbar keeps to the window's edge.
class ReadablePadding extends StatelessWidget {
  const ReadablePadding({
    super.key,
    required this.padding,
    required this.builder,
  });

  final EdgeInsets padding;
  final Widget Function(BuildContext context, EdgeInsets padding) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = (constraints.maxWidth - readableWidth) / 2;
        final inset = withIslandInset(context, padding);
        return builder(
          context,
          side <= 0
              ? inset
              : inset.copyWith(
                  left: inset.left + side,
                  right: inset.right + side,
                ),
        );
      },
    );
  }
}

/// The island's space as the first sliver of a [CustomScrollView].
class SliverIslandTopSpace extends StatelessWidget {
  const SliverIslandTopSpace({super.key});

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SizedBox(height: IslandScaffold.topSpace(context)),
  );
}
