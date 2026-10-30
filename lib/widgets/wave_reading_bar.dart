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
import 'package:musify/services/audio_levels.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/utilities/platform_utils.dart';
import 'package:musify/widgets/choice_bar.dart';

/// The Settings entry for [waveReading]. Choosing the precise reading on
/// Android asks for audio access, and stays simple without it.
class WaveReadingBar extends StatelessWidget {
  const WaveReadingBar({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;
    return ChoiceBar<WaveReading>(
      title: l10n.waveReading,
      icon: FluentIcons.data_bar_vertical_24_regular,
      setting: waveReading,
      choices: [
        (
          value: WaveReading.simple,
          label: l10n.waveReadingSimple,
          icon: FluentIcons.data_line_24_regular,
        ),
        (
          value: WaveReading.precise,
          label: isAndroidPlatform
              ? l10n.waveReadingPreciseAndroid
              : l10n.waveReadingPrecise,
          icon: FluentIcons.data_histogram_24_regular,
        ),
      ],
      onChosen: (reading) => _choose(context, reading),
    );
  }

  Future<void> _choose(BuildContext context, WaveReading reading) async {
    if (reading == WaveReading.precise && !await AudioLevels.requestAccess()) {
      waveReading.value = WaveReading.simple;
      if (context.mounted) showToast(context, context.l10n!.waveReadingDenied);
      return;
    }
    await addOrUpdateData<String>('settings', 'waveReading', reading.name);
  }
}
