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
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/bottom_sheet_bar.dart';
import 'package:musify/widgets/custom_bar.dart';

/// The Settings entry for [floatingEffect].
class FloatingEffectBar extends StatelessWidget {
  const FloatingEffectBar({super.key});

  static String label(AppLocalizations l10n, FloatingEffect effect) =>
      switch (effect) {
        FloatingEffect.solid => l10n.floatingEffectSolid,
        FloatingEffect.translucent => l10n.floatingEffectTranslucent,
        FloatingEffect.blurred => l10n.floatingEffectBlurred,
      };

  static const _icons = {
    FloatingEffect.solid: FluentIcons.square_24_filled,
    FloatingEffect.translucent: FluentIcons.square_multiple_24_regular,
    FloatingEffect.blurred: FluentIcons.blur_24_regular,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    return ValueListenableBuilder<FloatingEffect>(
      valueListenable: floatingEffect,
      builder: (context, effect, _) => CustomBar(
        l10n.floatingEffect,
        FluentIcons.layer_24_regular,
        description: label(l10n, effect),
        onTap: () => _choose(context),
      ),
    );
  }

  void _choose(BuildContext context) {
    final l10n = context.l10n!;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.floatingEffect),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final effect in FloatingEffect.values)
              BottomSheetBar(
                label(l10n, effect),
                () {
                  floatingEffect.value = effect;
                  addOrUpdateData<String>(
                    'settings',
                    'floatingEffect',
                    effect.name,
                  );
                  Navigator.pop(dialogContext);
                },
                floatingEffect.value == effect,
                icon: _icons[effect],
              ),
          ],
        ),
      ),
    );
  }
}
