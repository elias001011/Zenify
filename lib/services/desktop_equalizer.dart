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

import 'package:just_audio_media_kit/mediakit_player.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/models/equalizer_parameters.dart';
import 'package:musify/services/settings_manager.dart';

/// The equalizer of the desktop engine (libmpv). Five peaking filters sit in
/// one lavfi filter, installed once when an engine is prepared with the saved
/// gains and tuned live with `af-command` afterwards: filters must never be
/// added or removed on a playing output. It sits before the levels filter, so
/// the waves follow what is heard. Switched off, every gain is 0 and the
/// filter, in double precision, returns the samples it got to within rounding.
///
/// Follows [equalizerEnabled] and [equalizerBandGains], so a restored backup
/// reaches the engine like a change made on the page.
class DesktopEqualizer {
  DesktopEqualizer() {
    equalizerEnabled.addListener(_apply);
    equalizerBandGains.addListener(_apply);
  }

  /// mpv's label for the filter.
  static const _label = 'zeq';

  /// The usual Android centers, two octaves apart. Android reports its own
  /// range, almost always +-15 dB; the same keeps a synced backup intact.
  static const centerFrequencies = <double>[60, 230, 910, 3600, 14000];
  static const minDecibels = -15.0;
  static const maxDecibels = 15.0;

  /// The saved gains, one per band: clamped, and 0 where none is saved (a
  /// backup from a device with another band count).
  static List<double> savedGains() {
    final saved = equalizerBandGains.value;
    return [
      for (var i = 0; i < centerFrequencies.length; i++)
        if (i < saved.length) saved[i].clamp(minDecibels, maxDecibels) else 0.0,
    ];
  }

  static List<double> _activeGains() => equalizerEnabled.value
      ? savedGains()
      : List.filled(centerFrequencies.length, 0);

  static EqualizerParameters get parameters => (
    minDecibels: minDecibels,
    maxDecibels: maxDecibels,
    bands: [
      for (final (i, gain) in savedGains().indexed)
        (centerFrequency: centerFrequencies[i], gain: gain),
    ],
  );

  /// The name of band [i]'s filter, which `af-command` aims at.
  static String _stage(int i) => 'equalizer@b$i';

  /// The filter an engine is prepared with, for what is saved now.
  static String filter() {
    final gains = _activeGains();
    final bands = [
      for (var i = 0; i < gains.length; i++)
        '${_stage(i)}=f=${centerFrequencies[i]}:t=o:w=2:g=${gains[i]}:r=f64',
    ];
    return '@$_label:lavfi=[${bands.join(',')}]';
  }

  Future<void> _sending = Future.value();

  // One send after another, each with the gains of its own time.
  void _apply() => _sending = _sending.then((_) => _send());

  Future<void> _send() async {
    final player = MediaKitPlayer.latest;
    if (player == null) return;
    try {
      // The filter is there once the engine is prepared.
      await player.ready();
      final gains = _activeGains();
      for (var i = 0; i < gains.length; i++) {
        await player.mpvCommand([
          'af-command',
          _label,
          'gain',
          '${gains[i]}',
          _stage(i),
        ]);
      }
    } catch (error, stackTrace) {
      logger.log(
        'Could not tune the equalizer',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
