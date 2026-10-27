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
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/floating_surface.dart';

const double _islandHeight = 48;
const double _islandMargin = 12;

/// A page with the floating island in place of an app bar: back (when there
/// is somewhere to go back to), the page title and optional actions.
///
/// The body extends under the island and gets its height as top padding,
/// which scroll views read like the bottom padding of the floating dock.
class IslandScaffold extends StatelessWidget {
  const IslandScaffold({
    super.key,
    required this.title,
    required this.body,
    this.titleOpacity,
    this.actions = const [],
    this.brandTitle = false,
  });

  final String title;
  final Widget body;

  /// The app name in its logo font, for the home page.
  final bool brandTitle;

  /// Fades the title in and out, e.g. once a playlist's own title scrolls away.
  final ValueListenable<double>? titleOpacity;
  final List<Widget> actions;

  /// Space a page keeps free at the top for the island.
  static const double inset = _islandHeight + _islandMargin * 2;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return Scaffold(
      body: Stack(
        children: [
          MediaQuery(
            data: media.copyWith(
              padding: media.padding.copyWith(top: media.padding.top + inset),
            ),
            child: body,
          ),
          Positioned(
            top: media.padding.top + _islandMargin,
            left: _islandMargin,
            child: _Island(
              title: title,
              brandTitle: brandTitle,
              titleOpacity: titleOpacity,
              actions: actions,
              maxWidth: media.size.width - _islandMargin * 2,
            ),
          ),
        ],
      ),
    );
  }
}

class _Island extends StatelessWidget {
  const _Island({
    required this.title,
    required this.brandTitle,
    required this.titleOpacity,
    required this.actions,
    required this.maxWidth,
  });

  final String title;
  final bool brandTitle;
  final ValueListenable<double>? titleOpacity;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canPop = Navigator.of(context).canPop();

    Widget titleText = Padding(
      padding: EdgeInsets.only(left: canPop ? 2 : 14, right: 10),
      child: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: brandTitle
            ? TextStyle(
                fontSize: 21,
                fontFamily: 'paytoneOne',
                color: colorScheme.primary,
              )
            : TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
      ),
    );
    if (titleOpacity != null) {
      titleText = ValueListenableBuilder<double>(
        valueListenable: titleOpacity!,
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity.clamp(0.0, 1.0), child: child),
        child: titleText,
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: FloatingSurface(
        borderRadius: const BorderRadius.all(
          Radius.circular(_islandHeight / 2),
        ),
        child: SizedBox(
          height: _islandHeight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canPop)
                IconButton(
                  icon: const Icon(FluentIcons.arrow_left_24_regular),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              Flexible(child: titleText),
              ...actions,
              if (actions.isNotEmpty) const SizedBox(width: 2),
            ],
          ),
        ),
      ),
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
