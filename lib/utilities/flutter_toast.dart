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
}

const _maxToastWidth = 480.0;

ScaffoldMessengerState? _messengerFor(BuildContext context) =>
    toastMessengerKey.currentState ??
    (context.mounted ? ScaffoldMessenger.maybeOf(context) : null);

/// At most [_maxToastWidth] wide and centred, above [ToastInset.bottom].
EdgeInsets _toastMargin(ScaffoldMessengerState messenger) {
  final media = MediaQuery.maybeOf(messenger.context);
  final h = math.max(
    FloatingSurface.edgeMargin,
    ((media?.size.width ?? 0) - _maxToastWidth) / 2,
  );
  // A floating snack bar already stands above the safe area, which the
  // inset (from the window's bottom) includes.
  final safeBottom = media?.viewPadding.bottom ?? 0;
  final bottom = math.max(
    ToastInset.bottom - safeBottom,
    FloatingSurface.edgeMargin,
  );
  return EdgeInsets.fromLTRB(h, 0, h, bottom + 8);
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
