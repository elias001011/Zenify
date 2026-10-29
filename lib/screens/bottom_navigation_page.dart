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
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/main.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/flutter_bottom_sheet.dart'
    show closeCurrentBottomSheet;
import 'package:musify/widgets/app_logo.dart';
import 'package:musify/widgets/app_notice.dart';
import 'package:musify/widgets/floating_surface.dart';
import 'package:musify/widgets/mini_player.dart';

class BottomNavigationPage extends StatefulWidget {
  const BottomNavigationPage({required this.child, super.key});

  final StatefulNavigationShell child;

  @override
  State<BottomNavigationPage> createState() => _BottomNavigationPageState();
}

class _BottomNavigationPageState extends State<BottomNavigationPage> {
  late final _miniPlayerVisibilityStream = audioHandler.mediaItem
      .map((mediaItem) => mediaItem != null)
      .distinct();

  /// Keeps the branch navigators and their state when the layout switches
  /// between the dock and the rail, which moves them in the tree.
  final _contentKey = GlobalKey();

  /// Shared by this screen's blurred surfaces, kept across rebuilds.
  final _backdropKey = BackdropKey();

  @override
  void initState() {
    super.initState();
    offlineMode.addListener(_onOfflineModeChanged);
  }

  @override
  void dispose() {
    offlineMode.removeListener(_onOfflineModeChanged);
    super.dispose();
  }

  /// Search needs YouTube: going offline there returns home.
  void _onOfflineModeChanged() {
    if (offlineMode.value && widget.child.currentIndex == 1) {
      widget.child.goBranch(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreen = MediaQuery.sizeOf(context).width >= 600;
    final items = _navigationItems;
    final selected = items.indexWhere(
      (item) => item.shellIndex == widget.child.currentIndex,
    );

    return PopScope(
      canPop: widget.child.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;

        final currentIndex = widget.child.currentIndex;
        if (currentIndex != 0) {
          widget.child.goBranch(0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: BackdropGroup(
          backdropKey: _backdropKey,
          // Pages reach under the status bar, so their background does too;
          // each keeps its content and island below it.
          child: SafeArea(
            top: false,
            bottom: false,
            child: StreamBuilder<bool>(
              initialData: audioHandler.mediaItem.value != null,
              stream: _miniPlayerVisibilityStream,
              builder: (context, snapshot) {
                final playing = snapshot.data ?? false;
                return ValueListenableBuilder<bool>(
                  valueListenable: compactDesktopPlayer,
                  builder: (context, compact, _) => isLargeScreen && !compact
                      ? _buildDesktop(context, items, selected, playing)
                      : _buildMobile(
                          context,
                          items,
                          selected,
                          playing,
                          maxDockWidth: isLargeScreen ? 420 : null,
                        ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static const _margin = 12.0;
  static const _dockPadding = 6.0;
  static const _dockBarHeight = 44.0;

  static const _railWidth = 72.0;

  /// Pages extend under the floating elements, their backgrounds included;
  /// this is the space they keep free so no content stays hidden behind them.
  Widget _withInsets(
    BuildContext context, {
    required double bottom,
    double left = 0,
  }) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        padding: media.padding.copyWith(
          bottom: media.padding.bottom + bottom,
          left: media.padding.left + left,
        ),
      ),
      child: KeyedSubtree(key: _contentKey, child: widget.child),
    );
  }

  Widget _buildMobile(
    BuildContext context,
    List<_NavigationItem> items,
    int selected,
    bool playing, {
    double? maxDockWidth,
  }) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final dockHeight =
        _dockPadding * 2 +
        _dockBarHeight +
        (playing ? MiniPlayer.playerHeight : 0);

    return Stack(
      children: [
        _withInsets(context, bottom: _margin * 2 + dockHeight),
        Positioned(
          left: _margin,
          right: maxDockWidth == null ? _margin : null,
          width: maxDockWidth == null
              ? null
              : math.min(
                  maxDockWidth,
                  MediaQuery.sizeOf(context).width - _margin * 2,
                ),
          bottom: safeBottom + _margin,
          child: RepaintBoundary(
            child: FloatingSurface(
              grouped: true,
              padding: const EdgeInsets.all(_dockPadding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const NoticeSlot(),
                  if (playing) const MiniPlayer(),
                  SizedBox(
                    height: _dockBarHeight,
                    child: Row(
                      children: [
                        for (var i = 0; i < items.length; i++)
                          Expanded(
                            child: _DockButton(
                              item: items[i],
                              selected: i == selected,
                              onTap: () => _onTabTapped(i, items),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktop(
    BuildContext context,
    List<_NavigationItem> items,
    int selected,
    bool playing,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final settingsIndex = items.indexWhere((item) => item.shellIndex == 3);

    Widget railButton(int index) => _RailButton(
      item: items[index],
      selected: index == selected,
      onTap: () => _onTabTapped(index, items),
    );

    // The rail floats over the page like the dock on phones, so the page's
    // background reaches the window's edge behind it.
    return Stack(
      children: [
        _withInsets(
          context,
          bottom: playing ? MiniPlayer.playerHeight + _margin * 2 : 0,
          left: _margin + _railWidth,
        ),
        Positioned(
          left: _margin,
          // Below the status bar of a tablet or a phone on its side.
          top: MediaQuery.viewPaddingOf(context).top + _margin,
          bottom: _margin,
          child: RepaintBoundary(
            child: FloatingSurface(
              grouped: true,
              borderRadius: const BorderRadius.all(Radius.circular(24)),
              child: SizedBox(
                width: _railWidth,
                child: Column(
                  children: [
                    const SizedBox(height: 18),
                    AppLogo(size: 34, color: colorScheme.primary),
                    const SizedBox(height: 22),
                    for (var i = 0; i < items.length; i++)
                      if (i != settingsIndex) railButton(i),
                    const Spacer(),
                    if (settingsIndex != -1) railButton(settingsIndex),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (playing)
          const Positioned(
            left: _margin * 2 + _railWidth,
            right: _margin,
            bottom: _margin,
            child: RepaintBoundary(
              child: FloatingSurface(
                grouped: true,
                borderRadius: BorderRadius.all(Radius.circular(24)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [NoticeSlot(), MiniPlayer()],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Search opens from the island, so it has no tab of its own.
  List<_NavigationItem> get _navigationItems => [
    _NavigationItem(
      icon: FluentIcons.home_24_regular,
      selectedIcon: FluentIcons.home_24_filled,
      label: context.l10n?.home ?? 'Home',
      shellIndex: 0,
    ),
    _NavigationItem(
      icon: FluentIcons.book_24_regular,
      selectedIcon: FluentIcons.book_24_filled,
      label: context.l10n?.library ?? 'Library',
      shellIndex: 2,
    ),
    _NavigationItem(
      icon: FluentIcons.arrow_download_24_regular,
      selectedIcon: FluentIcons.arrow_download_24_filled,
      label: context.l10n?.downloads ?? 'Downloads',
      shellIndex: 4,
    ),
    _NavigationItem(
      icon: FluentIcons.settings_24_regular,
      selectedIcon: FluentIcons.settings_24_filled,
      label: context.l10n?.settings ?? 'Settings',
      shellIndex: 3,
    ),
  ];

  void _onTabTapped(int index, List<_NavigationItem> items) {
    final shellIndex = items[index].shellIndex;
    closeCurrentBottomSheet();
    // Tapping the open tab again takes it back to its start.
    widget.child.goBranch(
      shellIndex,
      initialLocation: shellIndex == widget.child.currentIndex,
    );
  }
}

/// Icon only; the label shows as a tooltip on long press or hover.
class _DockButton extends StatelessWidget {
  const _DockButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavigationItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // The whole slice of the dock answers a tap, not just the pill, so a
    // thumb slightly off the icon still switches tabs. The fixed slice also
    // lets the pill grow without moving its neighbours.
    return Tooltip(
      message: item.label,
      child: Semantics(
        selected: selected,
        button: true,
        label: item.label,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: Material(
              color: selected
                  ? colorScheme.secondaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(17),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(17),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  width: selected ? 60 : 44,
                  height: 34,
                  child: Icon(
                    selected ? item.selectedIcon : item.icon,
                    size: 22,
                    color: selected
                        ? colorScheme.onSecondaryContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _NavigationItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Tooltip(
        message: item.label,
        child: Material(
          color: selected ? colorScheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                selected ? item.selectedIcon : item.icon,
                color: selected
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationItem {
  const _NavigationItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.shellIndex,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int shellIndex;
}
