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

/// Where the notice goes while a page is in front: the height above the
/// window's bottom of what it floats over, how far that stands from each
/// side, and where the notice sits across that width.
typedef _Dock = ({
  double extent,
  double left,
  double right,
  AlignmentGeometry align,
});

const _noDock = (
  extent: 0.0,
  left: FloatingSurface.edgeMargin,
  right: FloatingSurface.edgeMargin,
  align: Alignment.center,
);

/// The notice on screen. [NoticeHost] floats it above everything, over the
/// dock when the shell's dock is in front (see [NoticeDockInset]) and near the
/// bottom edge otherwise. One surface, so text and chrome move as one.
abstract final class AppNotices {
  static final current = ValueNotifier<AppNotice?>(null);

  static final _dock = ValueNotifier<_Dock>(_noDock);

  /// Who reported [_dock], so that a page leaving the front does not undo
  /// what the page that came to the front has reported.
  static Object? _owner;
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

/// Reports where the notice goes while the page of the widget is in front,
/// and takes it back when the page leaves it or goes: only if it is still the
/// one that reported.
mixin _DockReporter<T extends StatefulWidget> on State<T> {
  _Dock? _reported;

  void _report({required bool inFront, required _Dock dock}) {
    if (!inFront) return _release();
    if (_reported == dock && AppNotices._owner == this) return;
    _reported = dock;
    AppNotices._owner = this;
    AppNotices._dock.value = dock;
  }

  void _release() {
    if (_reported == null) return;
    _reported = null;
    if (AppNotices._owner != this) return;
    AppNotices._owner = null;
    AppNotices._dock.value = _noDock;
  }

  @override
  void dispose() {
    // After this frame: the host must not rebuild while the tree is torn down.
    if (_reported != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _release());
    }
    super.dispose();
  }
}

/// Tells [NoticeHost] where the shell's dock is, so the notice floats right
/// above it. Reports only while its page is in front: under a full-screen
/// player or a sheet the dock is out of the way.
class NoticeDockInset extends StatefulWidget {
  const NoticeDockInset({
    required this.extent,
    this.left = FloatingSurface.edgeMargin,
    this.right = FloatingSurface.edgeMargin,
    super.key,
  });

  /// From the window's bottom to the top of the dock.
  final double extent;

  /// From the window's edges to the dock's.
  final double left;
  final double right;

  @override
  State<NoticeDockInset> createState() => _NoticeDockInsetState();
}

class _NoticeDockInsetState extends State<NoticeDockInset> with _DockReporter {
  @override
  Widget build(BuildContext context) {
    final inFront = ModalRoute.of(context)?.isCurrent ?? true;
    final dock = (
      extent: widget.extent,
      left: widget.left,
      right: widget.right,
      align: Alignment.center,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _report(inFront: inFront, dock: dock);
    });
    return const SizedBox.shrink();
  }
}

/// Makes the notice float right above [child], over its width, while the page
/// of the widget is in front: the player puts it above the progress bar, where
/// it covers no button.
class NoticeAbove extends StatefulWidget {
  const NoticeAbove({required this.child, super.key});

  final Widget child;

  @override
  State<NoticeAbove> createState() => _NoticeAboveState();
}

class _NoticeAboveState extends State<NoticeAbove> with _DockReporter {
  @override
  Widget build(BuildContext context) {
    final inFront = ModalRoute.of(context)?.isCurrent ?? true;
    final window = MediaQuery.sizeOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) return;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      _report(
        inFront: inFront,
        dock: (
          extent: window.height - rect.top,
          left: rect.left,
          right: window.width - rect.right,
          align: Alignment.center,
        ),
      );
    });
    return widget.child;
  }
}

/// Makes the notice sit in the bottom left corner of the window while the
/// page of the widget is in front, for a page whose middle is taken and whose
/// corner is free.
class NoticeCorner extends StatefulWidget {
  const NoticeCorner({super.key});

  @override
  State<NoticeCorner> createState() => _NoticeCornerState();
}

class _NoticeCornerState extends State<NoticeCorner> with _DockReporter {
  @override
  Widget build(BuildContext context) {
    final inFront = ModalRoute.of(context)?.isCurrent ?? true;
    final bottom = MediaQuery.paddingOf(context).bottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _report(
        inFront: inFront,
        dock: (
          // The host adds its gap to what it floats over.
          extent: bottom + FloatingSurface.edgeMargin - NoticeHost._gap,
          left: FloatingSurface.edgeMargin,
          right: FloatingSurface.edgeMargin,
          align: Alignment.centerLeft,
        ),
      );
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
        ValueListenableBuilder<_Dock>(
          valueListenable: AppNotices._dock,
          builder: (context, dock, _) => AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: dock.extent > 0 ? dock.left : FloatingSurface.edgeMargin,
            right: dock.extent > 0 ? dock.right : FloatingSurface.edgeMargin,
            bottom: dock.extent > 0 ? dock.extent + _gap : edge,
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
                    : Align(
                        key: ObjectKey(notice),
                        alignment: dock.align,
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
