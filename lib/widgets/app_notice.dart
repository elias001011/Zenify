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

import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/floating_surface.dart';

/// A short message shown for a moment, with an optional action.
class AppNotice {
  const AppNotice(this.text, {this.icon, this.actionLabel, this.onAction});

  final String text;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
}

/// The notice on screen. [NoticeHost] floats it above everything, over the
/// dock when the shell's dock is in front (see [NoticeDockInset]) and near the
/// bottom edge otherwise. One surface, so text and chrome move as one.
abstract final class AppNotices {
  static final current = ValueNotifier<AppNotice?>(null);

  /// Distance from the window's bottom to the top of the shell's dock while
  /// it is in front; 0 when nothing is in the way.
  static final _dockExtent = ValueNotifier<double>(0);
  static Timer? _timer;

  static void show(AppNotice notice, {required Duration duration}) {
    _timer?.cancel();
    current.value = notice;
    _timer = Timer(duration, dismiss);
  }

  /// Dismisses the current notice, or, given [notice], only if it is still
  /// the current one.
  static void dismiss([AppNotice? notice]) {
    if (notice != null && current.value != notice) return;
    _timer?.cancel();
    current.value = null;
  }
}

/// Tells [NoticeHost] how tall the shell's dock is, so the notice floats above
/// it. Reports only while its page is in front: under a full-screen player or
/// a sheet the dock is out of the way.
class NoticeDockInset extends StatefulWidget {
  const NoticeDockInset({required this.extent, super.key});

  /// From the window's bottom to the top of the dock.
  final double extent;

  @override
  State<NoticeDockInset> createState() => _NoticeDockInsetState();
}

class _NoticeDockInsetState extends State<NoticeDockInset> {
  double _reported = 0;

  void _report(double extent) {
    if (extent == _reported) return;
    _reported = extent;
    AppNotices._dockExtent.value = extent;
  }

  @override
  void dispose() {
    // After this frame: the host must not rebuild while the tree is torn down.
    if (_reported != 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => AppNotices._dockExtent.value = 0,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inFront = ModalRoute.of(context)?.isCurrent ?? true;
    final extent = inFront ? widget.extent : 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _report(extent);
    });
    return const SizedBox.shrink();
  }
}

/// Floats the notice above everything: over the dock if one is in front,
/// near the bottom edge otherwise.
class NoticeHost extends StatelessWidget {
  const NoticeHost({required this.child, super.key});

  final Widget child;

  static const _gap = 8.0;

  @override
  Widget build(BuildContext context) {
    final edge =
        MediaQuery.paddingOf(context).bottom + FloatingSurface.edgeMargin;
    return Stack(
      children: [
        child,
        ValueListenableBuilder<double>(
          valueListenable: AppNotices._dockExtent,
          builder: (context, extent, _) => AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: FloatingSurface.edgeMargin,
            right: FloatingSurface.edgeMargin,
            bottom: extent > 0 ? extent + _gap : edge,
            child: ValueListenableBuilder<AppNotice?>(
              valueListenable: AppNotices.current,
              builder: (context, notice, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.4),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: notice == null
                    ? const SizedBox.shrink()
                    : Center(
                        key: ObjectKey(notice),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: _NoticePill(notice),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NoticePill extends StatelessWidget {
  const _NoticePill(this.notice);

  final AppNotice notice;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final actionLabel = notice.actionLabel;
    return _SwipeDownToDismiss(
      notice: notice,
      child: FloatingSurface(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36),
            child: Row(
              children: [
                Icon(
                  notice.icon ?? FluentIcons.checkmark_circle_20_regular,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    notice.text,
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                if (actionLabel != null)
                  TextButton(
                    onPressed: () {
                      AppNotices.dismiss();
                      notice.onAction?.call();
                    },
                    child: Text(actionLabel),
                  )
                else
                  const SizedBox(width: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Moves the whole notice with a downward drag and dismisses it once dragged
/// or flung far enough, as Musify's snack bars did; otherwise it springs back.
class _SwipeDownToDismiss extends StatefulWidget {
  const _SwipeDownToDismiss({required this.notice, required this.child});

  final AppNotice notice;
  final Widget child;

  @override
  State<_SwipeDownToDismiss> createState() => _SwipeDownToDismissState();
}

class _SwipeDownToDismissState extends State<_SwipeDownToDismiss> {
  static const _maxOffset = 80.0;

  double _offset = 0;

  void _end(DragEndDetails details) {
    if (_offset > 24 || (details.primaryVelocity ?? 0) > 300) {
      AppNotices.dismiss(widget.notice);
    } else {
      setState(() => _offset = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: (details) => setState(
        () => _offset = (_offset + details.delta.dy).clamp(0, _maxOffset),
      ),
      onVerticalDragEnd: _end,
      onVerticalDragCancel: () => setState(() => _offset = 0),
      child: Opacity(
        opacity: 1 - 0.6 * _offset / _maxOffset,
        child: Transform.translate(
          offset: Offset(0, _offset),
          child: widget.child,
        ),
      ),
    );
  }
}
