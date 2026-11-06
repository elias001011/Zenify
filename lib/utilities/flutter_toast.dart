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
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/floating_surface.dart';

/// The messenger the toasts go through, whoever asks: many callers show a toast
/// after the dialog or sheet they were called from has closed.
final toastMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// How far above the window's bottom a toast has to stay to clear what floats
/// over the pages. The shell, which owns the dock (or the rail and the wide
/// mini player), keeps it up to date.
abstract final class ToastInset {
  static double bottom = 0;

  /// Where the dock stands when it is narrower than the window and not
  /// centred (the compact desktop player keeps it to the left): the toast
  /// goes over it, not beside it. Null: the toast is centred.
  static ({double left, double width})? dock;
}

const _maxToastWidth = 480.0;

ScaffoldMessengerState? _messengerFor(BuildContext context) =>
    toastMessengerKey.currentState ??
    (context.mounted ? ScaffoldMessenger.maybeOf(context) : null);

/// At most [_maxToastWidth] wide, centred or over the dock when that keeps to
/// one side, above [ToastInset.bottom].
EdgeInsets _toastMargin(ScaffoldMessengerState messenger) {
  final media = MediaQuery.maybeOf(messenger.context);
  final windowWidth = media?.size.width ?? 0;
  final dock = ToastInset.dock;
  final double left;
  final double right;
  if (dock == null) {
    left = right = math.max(
      FloatingSurface.edgeMargin,
      (windowWidth - _maxToastWidth) / 2,
    );
  } else {
    final width = math.min(dock.width, _maxToastWidth);
    left = dock.left;
    right = math.max(FloatingSurface.edgeMargin, windowWidth - left - width);
  }
  // A floating snack bar already stands above the safe area, which the
  // inset (from the window's bottom) includes.
  final safeBottom = media?.viewPadding.bottom ?? 0;
  final bottom = math.max(
    ToastInset.bottom - safeBottom,
    FloatingSurface.edgeMargin,
  );
  return EdgeInsets.fromLTRB(left, 0, right, bottom + 8);
}

Widget _toastContent(IconData icon, String text) => Row(
  children: [
    Builder(
      builder: (context) =>
          Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
    ),
    const SizedBox(width: 12),
    Expanded(child: Text(text)),
  ],
);

/// Shows [text] in a snack bar. [context] is only the fallback for an app that
/// has no [toastMessengerKey]; it need not be mounted any more.
void showToast(
  BuildContext context,
  String text, {
  Duration duration = const Duration(seconds: 3),
  IconData? icon,
}) {
  final messenger = _messengerFor(context);
  if (messenger == null) return;

  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: _toastMargin(messenger),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      content: _toastContent(
        icon ?? FluentIcons.checkmark_circle_20_regular,
        text,
      ),
      duration: duration,
    ),
  );
}

void showToastWithButton(
  BuildContext context,
  String text,
  String buttonName,
  VoidCallback onPressedToast, {
  Duration duration = const Duration(seconds: 3),
  IconData? icon,
}) {
  final messenger = _messengerFor(context);
  if (messenger == null) return;

  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: _toastMargin(messenger),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      content: _toastContent(icon ?? FluentIcons.info_20_regular, text),
      action: SnackBarAction(
        label: buttonName,
        onPressed: () => onPressedToast(),
      ),
      persist: false,
      duration: duration,
    ),
  );
}
