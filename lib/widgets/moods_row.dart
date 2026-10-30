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
import 'package:musify/services/moods/moods_service.dart';
import 'package:musify/utilities/flutter_toast.dart';
import 'package:musify/widgets/section_header.dart';

/// Each mood's icon and its colour, from the app's own palette so they read
/// in light and dark.
IconData moodIcon(Mood mood) => switch (mood) {
  Mood.mix => FluentIcons.sparkle_24_filled,
  Mood.feelGood => FluentIcons.emoji_laugh_24_regular,
  Mood.chill => FluentIcons.leaf_two_24_regular,
  Mood.energize => FluentIcons.flash_24_regular,
  Mood.focus => FluentIcons.target_24_regular,
  Mood.party => FluentIcons.balloon_24_regular,
  Mood.romance => FluentIcons.heart_pulse_24_regular,
  Mood.sad => FluentIcons.emoji_sad_24_regular,
  Mood.workout => FluentIcons.run_24_regular,
  Mood.commute => FluentIcons.vehicle_car_24_regular,
  Mood.sleep => FluentIcons.weather_moon_24_regular,
};

Color _moodHue(Mood mood) => switch (mood) {
  Mood.mix => const Color(0xFF8E7CFF),
  Mood.feelGood => const Color(0xFFFFB020),
  Mood.chill => const Color(0xFF3CC8A0),
  Mood.energize => const Color(0xFFFF6B3D),
  Mood.focus => const Color(0xFF4C9BFF),
  Mood.party => const Color(0xFFE85CD0),
  Mood.romance => const Color(0xFFFF5C7A),
  Mood.sad => const Color(0xFF6F8CB8),
  Mood.workout => const Color(0xFFFF8A00),
  Mood.commute => const Color(0xFF29B6F6),
  Mood.sleep => const Color(0xFF7E6BD6),
};

/// The Moods on Home: round buttons, not playlists. A tap starts a queue
/// made for the user right away, and it never runs out.
class MoodsRow extends StatefulWidget {
  const MoodsRow({super.key});

  @override
  State<MoodsRow> createState() => _MoodsRowState();
}

class _MoodsRowState extends State<MoodsRow> {
  Mood? _starting;

  Future<void> _start(Mood mood) async {
    if (_starting != null) return;
    setState(() => _starting = mood);
    final started = await moodsService.play(mood).catchError((_) => false);
    if (!mounted) return;
    setState(() => _starting = null);
    if (!started) showToast(context, context.l10n!.moodUnavailable);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: context.l10n!.moods,
          icon: FluentIcons.sparkle_24_filled,
        ),
        SizedBox(
          height: 104,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: Mood.values.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final mood = Mood.values[index];
              return _MoodButton(
                mood: mood,
                busy: _starting == mood,
                onTap: () => _start(mood),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MoodButton extends StatelessWidget {
  const _MoodButton({
    required this.mood,
    required this.busy,
    required this.onTap,
  });

  final Mood mood;
  final bool busy;
  final VoidCallback onTap;

  static const _size = 68.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hue = _moodHue(mood);
    final label = moodLabel(context.l10n!, mood);
    final isMix = mood == Mood.mix;

    final circle = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isMix
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [scheme.primary, hue, scheme.tertiary],
              )
            : null,
        color: isMix ? null : scheme.surfaceContainerHigh,
      ),
      child: SizedBox.square(
        dimension: _size,
        child: Center(
          child: isMix
              ? Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : Icon(moodIcon(mood), color: hue, size: 28),
        ),
      ),
    );

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              const SizedBox(height: 4),
              Stack(
                alignment: Alignment.center,
                children: [
                  circle,
                  if (busy)
                    SizedBox.square(
                      dimension: _size + 6,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: hue,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (!isMix)
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
