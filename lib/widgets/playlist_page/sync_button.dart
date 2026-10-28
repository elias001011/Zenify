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
import 'package:musify/extensions/l10n.dart';

/// Refreshes a playlist or artist; the icon spins until [onSync] finishes.
class SyncButton extends StatefulWidget {
  const SyncButton({super.key, required this.onSync});

  final Future<void> Function() onSync;

  @override
  State<SyncButton> createState() => _SyncButtonState();
}

class _SyncButtonState extends State<SyncButton>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    setState(() {});
    unawaited(_spin.repeat());
    try {
      await widget.onSync();
    } finally {
      if (mounted) {
        // Ends the turn it is in instead of snapping back.
        await _spin.animateTo(1, duration: _spin.duration! * (1 - _spin.value));
        _spin.reset();
        if (mounted) setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      icon: RotationTransition(
        turns: _spin,
        child: const Icon(FluentIcons.arrow_sync_24_filled),
      ),
      iconSize: 24,
      onPressed: _spin.isAnimating ? null : _sync,
      tooltip: context.l10n!.update,
    );
  }
}
