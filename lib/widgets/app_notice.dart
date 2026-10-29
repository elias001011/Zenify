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

/// The notice on screen. The dock (or the desktop's floating player) grows
/// to show it while its page is in front; otherwise [NoticeHost] floats it
/// where the dock would be.
abstract final class AppNotices {
  static final current = ValueNotifier<AppNotice?>(null);

  /// How many [NoticeSlot]s are on screen to show it.
  static final _slots = ValueNotifier<int>(0);
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

/// The notice inside a floating surface, growing it upwards.
class NoticeSlot extends StatefulWidget {
  const NoticeSlot({super.key});

  @override
  State<NoticeSlot> createState() => _NoticeSlotState();
}

class _NoticeSlotState extends State<NoticeSlot> {
  bool _registered = false;

  void _register(bool register) {
    if (register == _registered) return;
    _registered = register;
    AppNotices._slots.value += register ? 1 : -1;
  }

  @override
  void dispose() {
    // After this frame: the host must not rebuild while the tree is torn down.
    if (_registered) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => AppNotices._slots.value--,
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Not in front (a full-screen player, a sheet): the host shows it.
    final inFront = ModalRoute.of(context)?.isCurrent ?? true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _register(inFront);
    });

    return ValueListenableBuilder<AppNotice?>(
      valueListenable: AppNotices.current,
      builder: (context, notice, _) => AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.bottomCenter,
        child: notice == null || !inFront
            ? const SizedBox(width: double.infinity)
            : _NoticeContent(notice, key: ObjectKey(notice)),
      ),
    );
  }
}

/// Floats the notice above everything when no [NoticeSlot] can show it.
class NoticeHost extends StatelessWidget {
  const NoticeHost({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom + 12;
    return Stack(
      children: [
        child,
        Positioned(
          left: 12,
          right: 12,
          bottom: bottom,
          child: ValueListenableBuilder<int>(
            valueListenable: AppNotices._slots,
            builder: (context, slots, _) => ValueListenableBuilder<AppNotice?>(
              valueListenable: AppNotices.current,
              builder: (context, notice, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: notice == null || slots > 0
                    ? const SizedBox.shrink()
                    : Center(
                        key: ObjectKey(notice),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: FloatingSurface(child: _NoticeContent(notice)),
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

class _NoticeContent extends StatelessWidget {
  const _NoticeContent(this.notice, {super.key});

  final AppNotice notice;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final actionLabel = notice.actionLabel;
    return _SwipeDownToDismiss(
      notice: notice,
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
                  style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
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
    );
  }
}

/// Follows a downward drag and dismisses the notice once dragged or flung
/// far enough, as Musify's snack bars did; otherwise it springs back.
/// Clipped, so it doesn't slide over the mini player below it.
class _SwipeDownToDismiss extends StatefulWidget {
  const _SwipeDownToDismiss({required this.notice, required this.child});

  final AppNotice notice;
  final Widget child;

  @override
  State<_SwipeDownToDismiss> createState() => _SwipeDownToDismissState();
}

class _SwipeDownToDismissState extends State<_SwipeDownToDismiss> {
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
      onVerticalDragUpdate: (details) =>
          setState(() => _offset = (_offset + details.delta.dy).clamp(0, 80)),
      onVerticalDragEnd: _end,
      onVerticalDragCancel: () => setState(() => _offset = 0),
      child: ClipRect(
        child: Transform.translate(
          offset: Offset(0, _offset),
          child: widget.child,
        ),
      ),
    );
  }
}
