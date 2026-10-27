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
import 'package:musify/constants/app_constants.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/services/data_manager.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/custom_bar.dart';
import 'package:musify/widgets/section_header.dart';
import 'package:musify/widgets/shapes/four_sided_cookie_shape.dart';

/// Window and layout options, shown on Windows, Linux and macOS only.
class DesktopSettingsSection extends StatelessWidget {
  const DesktopSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n!;

    return Column(
      children: [
        SectionHeader(title: l10n.desktop, icon: FluentIcons.desktop_24_filled),
        const _InterfaceScaleBar(),
        _SettingSwitch(
          title: l10n.startMaximized,
          description: l10n.startMaximizedDescription,
          icon: FluentIcons.maximize_24_regular,
          setting: startMaximized,
          storageKey: 'startMaximized',
        ),
        _SettingSwitch(
          title: l10n.customTitleBar,
          description: l10n.customTitleBarDescription,
          icon: FluentIcons.color_background_24_regular,
          setting: customTitleBar,
          storageKey: 'customTitleBar',
          borderRadius: commonCustomBarRadiusLast,
        ),
      ],
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.title,
    required this.description,
    required this.icon,
    required this.setting,
    required this.storageKey,
    this.borderRadius = BorderRadius.zero,
  });

  final String title;
  final String description;
  final IconData icon;
  final ValueNotifier<bool> setting;
  final String storageKey;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: setting,
      builder: (context, value, _) => CustomBar(
        title,
        icon,
        description: description,
        borderRadius: borderRadius,
        onTap: () => _set(!value),
        trailing: Switch(value: value, onChanged: _set),
      ),
    );
  }

  void _set(bool value) {
    setting.value = value;
    addOrUpdateData<bool>('settings', storageKey, value);
  }
}

/// A [CustomBar] with the scale slider underneath.
class _InterfaceScaleBar extends StatefulWidget {
  const _InterfaceScaleBar();

  @override
  State<_InterfaceScaleBar> createState() => _InterfaceScaleBarState();
}

class _InterfaceScaleBarState extends State<_InterfaceScaleBar> {
  static const _step = 0.05;

  // Applied on release: rescaling while dragging moves the slider away.
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n!;

    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: commonCustomBarRadiusFirst,
      clipBehavior: Clip.antiAlias,
      child: ValueListenableBuilder<double>(
        valueListenable: interfaceScale,
        builder: (context, applied, _) {
          final scale = _dragValue ?? applied;
          final percent = '${(scale * 100).round()}%';
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Column(
              children: [
                Row(
                  children: [
                    FourSidedCookieShape(
                      size: 52,
                      color: colorScheme.secondaryContainer,
                      child: Icon(
                        FluentIcons.text_font_size_24_regular,
                        size: 26,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.interfaceScale,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.interfaceScaleDescription,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        percent,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 54),
                  child: SliderTheme(
                    data: SliderTheme.of(
                      context,
                    ).copyWith(tickMarkShape: SliderTickMarkShape.noTickMark),
                    child: Slider(
                      value: scale,
                      min: minInterfaceScale,
                      max: maxInterfaceScale,
                      divisions:
                          ((maxInterfaceScale - minInterfaceScale) / _step)
                              .round(),
                      label: percent,
                      onChanged: (value) => setState(() => _dragValue = value),
                      onChangeEnd: _save,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _save(double value) {
    setState(() => _dragValue = null);
    final rounded = (value / _step).round() * _step;
    interfaceScale.value = double.parse(rounded.toStringAsFixed(2));
    addOrUpdateData<double>('settings', 'interfaceScale', interfaceScale.value);
  }
}
