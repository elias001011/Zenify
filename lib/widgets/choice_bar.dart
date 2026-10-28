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

import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/bottom_sheet_bar.dart';
import 'package:musify/widgets/custom_bar.dart';

typedef Choice<T> = ({T value, String label, IconData icon});

/// A settings row showing the current choice of [setting], picked from a
/// dialog of [choices]; [onChosen] saves it.
class ChoiceBar<T> extends StatelessWidget {
  const ChoiceBar({
    super.key,
    required this.title,
    required this.icon,
    required this.setting,
    required this.choices,
    required this.onChosen,
  });

  final String title;
  final IconData icon;
  final ValueNotifier<T> setting;
  final List<Choice<T>> choices;
  final ValueChanged<T> onChosen;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<T>(
      valueListenable: setting,
      builder: (context, value, _) => CustomBar(
        title,
        icon,
        description: choices.firstWhere((c) => c.value == value).label,
        onTap: () => _choose(context),
      ),
    );
  }

  void _choose(BuildContext context) {
    // The dialog sits on the root navigator: pop it with its own context,
    // or the settings page closes instead (see gokadzev/Musify#1010).
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final choice in choices)
              BottomSheetBar(
                choice.label,
                () {
                  Navigator.pop(dialogContext);
                  setting.value = choice.value;
                  onChosen(choice.value);
                },
                setting.value == choice.value,
                icon: choice.icon,
              ),
          ],
        ),
      ),
    );
  }
}
