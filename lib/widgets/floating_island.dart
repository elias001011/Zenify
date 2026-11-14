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
import 'package:musify/constants/motion.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/screens/search_page.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/floating_surface.dart';
import 'package:musify/widgets/spinner.dart';

const double _islandHeight = 44;
const double _islandMargin = FloatingSurface.edgeMargin;

/// The search field of a page that is, above all, a search: the island shows
/// it all the time, bound to the page's own [controller] and [focusNode], in
/// place of the title and the search shortcut. It never closes; Back leaves
/// the page.
class IslandPageSearch {
  const IslandPageSearch({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    this.onChanged,
    this.loading,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String>? onChanged;

  /// While true, the field's search icon turns into a spinner.
  final ValueListenable<bool>? loading;
}

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
    this.headerTitleKey,
    this.actions = const [],
    this.onBack,
    this.onFilter,
    this.globalSearch = true,
    this.pageSearch,
    this.background,
  }) : assert(
         pageSearch == null || onFilter == null,
         'The island field is a page filter or a page search, not both',
       );

  final String title;
  final Widget body;

  /// Makes the island this page's search field, kept open.
  final IslandPageSearch? pageSearch;

  /// Behind the body and the island, e.g. the page glow; it does not scroll.
  final Widget? background;

  /// Turns the search shortcut into a live filter of this page (playlists).
  final ValueChanged<String>? onFilter;

  /// Offer the search shortcut, which opens the search page on Enter.
  final bool globalSearch;

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
  late final _titleShown = ValueNotifier<bool>(widget.headerTitleKey == null);
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
    if (widget.headerTitleKey != oldWidget.headerTitleKey) {
      _titleShown.value = widget.headerTitleKey == null;
    }
  }

  @override
  void dispose() {
    _titleShown.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollUpdateNotification notification) {
    if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
      _scheduleTitleVisibility();
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
        fit: StackFit.expand,
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
              pageSearch: widget.pageSearch,
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
    required this.pageSearch,
    required this.maxWidth,
  });

  final String title;
  final ValueListenable<bool> titleShown;
  final List<Widget> actions;
  final VoidCallback? onBack;
  final ValueChanged<String>? onFilter;
  final bool globalSearch;
  final IslandPageSearch? pageSearch;
  final double maxWidth;

  @override
  State<_Island> createState() => _IslandState();
}

class _IslandState extends State<_Island> with SingleTickerProviderStateMixin {
  static const _searchWidth = 480.0;

  final _ownController = TextEditingController();
  final _ownFocusNode = FocusNode();
  bool _searching = false;

  // 1 with the field shown. Each part sizes itself, so the title's own
  // resize carries the buttons after it along with the edge.
  late final _field = AnimationController(
    vsync: this,
    duration: Motion.medium,
    value: widget.pageSearch != null ? 1 : 0,
  )..addStatusListener((_) => setState(() {}));
  late final _fieldCurve = CurvedAnimation(
    parent: _field,
    curve: Motion.curve,
    reverseCurve: Motion.curve.flipped,
  );

  // A page search brings its own, which the page owns.
  TextEditingController get _controller =>
      widget.pageSearch?.controller ?? _ownController;
  FocusNode get _focusNode => widget.pageSearch?.focusNode ?? _ownFocusNode;

  @override
  void dispose() {
    offlineMode.removeListener(_onOfflineChanged);
    _fieldCurve.dispose();
    _field.dispose();
    _ownController.dispose();
    _ownFocusNode.dispose();
    super.dispose();
  }

  void _openSearch() {
    setState(() => _searching = true);
    _field.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _closeSearch() {
    _controller.clear();
    widget.onFilter?.call('');
    setState(() => _searching = false);
    if (widget.pageSearch == null) {
      _ownFocusNode.unfocus();
      _field.reverse();
    }
  }

  /// The clear button of a page search: the text goes, the focus stays.
  void _clearText() {
    _controller.clear();
    widget.pageSearch?.onChanged?.call('');
    _focusNode.requestFocus();
  }

  void _submit(String query) {
    _focusNode.unfocus();
    if (widget.pageSearch case final page?) {
      page.onSubmitted(query);
      return;
    }
    final trimmed = query.trim();
    if (trimmed.isEmpty || offlineMode.value) return;
    if (widget.onFilter != null && !globalSearchOnEnter.value) return;
    // Keep a page filter (and its text) intact for Back from global search.
    if (widget.onFilter == null) _closeSearch();
    openSearch(trimmed);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isPageSearch = widget.pageSearch != null;
    if (key == LogicalKeyboardKey.escape) {
      // A page search stays open; Escape only leaves the field.
      if (isPageSearch) {
        _focusNode.unfocus();
      } else {
        _closeSearch();
      }
      return KeyEventResult.handled;
    }
    if (isPageSearch && key == LogicalKeyboardKey.numpadEnter) {
      _submit(_controller.text);
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
    final fieldWidth = widget.maxWidth < _searchWidth
        ? widget.maxWidth
        : _searchWidth;
    final fieldShown =
        _field.status == AnimationStatus.forward || _field.isCompleted;
    Widget bar() => _part(
      key: const ValueKey('bar'),
      factor: ReverseAnimation(_fieldCurve),
      shown: !fieldShown,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: _buildBar(context, showSearch),
      ),
    );
    Widget field() => _part(
      key: const ValueKey('field'),
      factor: _fieldCurve,
      shown: fieldShown,
      child: SizedBox(width: fieldWidth, child: _buildSearchField(context)),
    );

    // Its own layer: with blur on, resizing would repaint the page each frame.
    return PopScope(
      // Back closes an open search before it leaves the page (a page search
      // never closes).
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: RepaintBoundary(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          child: FloatingSurface(
            borderRadius: const BorderRadius.all(
              Radius.circular(_islandHeight / 2),
            ),
            child: SizedBox(
              height: _islandHeight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                // The part coming in first, so it stays put as the edge
                // reveals it; the one leaving empties at once.
                children: [
                  if (fieldShown) field() else bar(),
                  if (_field.isAnimating)
                    if (fieldShown) bar() else field(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The bar or the field, at [factor] of its width; the one leaving is
  /// blank and takes no focus or taps.
  Widget _part({
    required Key key,
    required Animation<double> factor,
    required bool shown,
    required Widget child,
  }) => AnimatedBuilder(
    key: key,
    animation: factor,
    // Not clipped here: the island's own shape cuts what passes its edge.
    builder: (context, child) => Align(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: factor.value,
      child: child,
    ),
    child: ExcludeFocus(
      excluding: !shown,
      child: IgnorePointer(
        ignoring: !shown,
        child: Opacity(opacity: shown ? 1 : 0, child: child),
      ),
    ),
  );

  /// Only pages pushed over another one in their own navigator: a tab's
  /// first page has nowhere to go back to.
  bool _canPop(BuildContext context) =>
      !(ModalRoute.of(context)?.isFirst ?? true);

  Widget _backButton(BuildContext context) => IconButton(
    icon: const Icon(FluentIcons.arrow_left_24_regular),
    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
    onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
  );

  Widget _buildBar(BuildContext context, bool showSearch) {
    final colorScheme = Theme.of(context).colorScheme;
    final canPop = _canPop(context);

    final titleText = Padding(
      padding: EdgeInsetsDirectional.only(start: canPop ? 2 : 14, end: 10),
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
          if (canPop) _backButton(context),
          if (widget.title.isNotEmpty)
            Flexible(
              // Empty while hidden, so the island stays compact.
              child: AnimatedSize(
                duration: Motion.medium,
                curve: Motion.curve,
                alignment: AlignmentDirectional.centerStart,
                child: titleShown
                    ? TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Motion.medium,
                        builder: (context, opacity, child) =>
                            Opacity(opacity: opacity, child: child),
                        child: titleText,
                      )
                    : const SizedBox.shrink(),
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
    final page = widget.pageSearch;
    final canPop = page != null && _canPop(context);
    final searchIcon = Icon(
      FluentIcons.search_24_regular,
      size: 20,
      color: colorScheme.onSurfaceVariant,
    );
    return Row(
      children: [
        if (canPop) _backButton(context),
        SizedBox(width: canPop ? 2 : 14),
        if (page?.loading case final notifier?)
          ValueListenableBuilder<bool>(
            valueListenable: notifier,
            builder: (context, loading, _) =>
                loading ? const Spinner(size: 20, strokeWidth: 2) : searchIcon,
          )
        else
          searchIcon,
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
              onChanged: page == null ? widget.onFilter : page.onChanged,
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
        if (page == null)
          IconButton(
            icon: const Icon(FluentIcons.dismiss_24_regular),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: _closeSearch,
          )
        else
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox(width: 12)
                : IconButton(
                    icon: const Icon(FluentIcons.dismiss_24_regular),
                    tooltip: context.l10n!.clear,
                    onPressed: _clearText,
                  ),
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

/// [padding] with the island's space on top and whatever room either side
/// centres the content within [readableWidth]. The margins stay part of the
/// scroll view, so it scrolls from anywhere and its scrollbar keeps to the
/// window's edge. Read it with the page's own context, outside the
/// [IslandScaffold], where the window's width less the rail is the page's.
EdgeInsets readableInset(BuildContext context, EdgeInsets padding) {
  final inset = withIslandInset(context, padding);
  final width =
      MediaQuery.sizeOf(context).width - MediaQuery.paddingOf(context).left;
  final side = (width - readableWidth) / 2;
  return side <= 0
      ? inset
      : inset.copyWith(left: inset.left + side, right: inset.right + side);
}

/// The island's space as the first sliver of a [CustomScrollView].
class SliverIslandTopSpace extends StatelessWidget {
  const SliverIslandTopSpace({super.key});

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: SizedBox(height: IslandScaffold.topSpace(context)),
  );
}
