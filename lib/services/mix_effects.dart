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

import 'package:hive_ce/hive_ce.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/mediakit_player.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/services/mix_transition.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/platform_utils.dart';

/// Turns the bass, mids and treble of each player down and up for the Mix.
///
/// Desktop: three filters in libmpv, untouched at 0 dB, moved by commands.
/// Android: the player's own equalizer, on top of the bands the user set.
class MixEffects {
  MixEffects({required this.equalizerOf});

  /// The filters every desktop player gets while the Mix is on. At 0 dB each
  /// passes the sound as it is.
  static const desktopFilters = [
    '@zmixl:lavfi=[bass=g=0:f=200]',
    '@zmixm:lavfi=[equalizer=f=1000:t=o:w=2:g=0]',
    '@zmixh:lavfi=[treble=g=0:f=4000]',
  ];

  static const desktopFrequencies = [60.0, 230.0, 910.0, 3600.0, 14000.0];
  static List<double> get desktopGains {
    final raw = Hive.box('settings').get('desktopEqualizerGains');
    return List.generate(
      5,
      (i) => raw is List && i < raw.length && raw[i] is num
          ? (raw[i] as num).toDouble().clamp(-12.0, 12.0)
          : 0.0,
    );
  }

  static List<String> get userFilters => [
    for (var i = 0; i < 5; i++)
      '@zuser$i:lavfi=[equalizer=f=${desktopFrequencies[i]}:t=o:w=2:g=${equalizerEnabled.value ? desktopGains[i] : 0}]',
  ];

  Future<void> updateDesktopEq() async {
    for (final entry in _mpv.entries.toList()) {
      final mpv = entry.value;
      if (mpv == null || entry.key.processingState == ProcessingState.idle)
        continue;
      if (!(await mpv.getMpvProperty('af')).contains('zuser0')) continue;
      for (var i = 0; i < 5; i++) {
        await mpv.mpvCommand([
          'af-command',
          'zuser$i',
          'gain',
          '${equalizerEnabled.value ? desktopGains[i] : 0}',
          'equalizer',
        ]);
      }
    }
  }

  final AndroidEqualizer? Function(AudioPlayer player) equalizerOf;

  final _mpv = <AudioPlayer, MediaKitPlayer?>{};
  final _parameters = <AndroidEqualizer, AndroidEqualizerParameters>{};
  final _sent = <AudioPlayer, MixBands>{};
  final _wanted = <AudioPlayer, MixBands>{};
  final _writing = <AudioPlayer>{};

  /// [player] just loaded a song: on desktop that may be a new libmpv, which
  /// starts with its bands untouched.
  void loaded(AudioPlayer player) {
    if (!isDesktopPlatform) return;
    final mpv = MediaKitPlayer.lastLoaded;
    if (_mpv[player] != mpv) {
      _mpv[player] = mpv;
      _sent.remove(player);
      unawaited(
        updateDesktopEq().catchError((Object e, StackTrace stack) {
          logger.log(
            'Equalizer: desktop setup failed',
            error: e,
            stackTrace: stack,
          );
        }),
      );
    }
  }

  /// Puts [bands] to [player]. Calls may come faster than the player takes
  /// them: the newest wins.
  void write(AudioPlayer player, MixBands bands) {
    _wanted[player] = bands;
    if (_writing.add(player)) unawaited(_drain(player));
  }

  Future<void> _drain(AudioPlayer player) async {
    try {
      while (_wanted[player] != _sent[player]) {
        final bands = _wanted[player]!;
        final before = _sent[player] ?? mixFlat;
        _sent[player] = bands;
        if (isDesktopPlatform) {
          await _writeDesktop(player, before, bands);
        } else if (isAndroidPlatform) {
          await _writeAndroid(player, bands);
        }
      }
    } catch (e, stackTrace) {
      logger.log('Mix: setting bands failed', error: e, stackTrace: stackTrace);
    } finally {
      _writing.remove(player);
    }
  }

  Future<void> _writeDesktop(
    AudioPlayer player,
    MixBands before,
    MixBands bands,
  ) async {
    final mpv = _mpv[player];
    if (mpv == null) return;
    for (final (label, target, was, now) in [
      ('zmixl', 'bass', before.low, bands.low),
      ('zmixm', 'equalizer', before.mid, bands.mid),
      ('zmixh', 'treble', before.high, bands.high),
    ]) {
      if (was == now) continue;
      try {
        await mpv.mpvCommand([
          'af-command',
          label,
          'gain',
          now.toStringAsFixed(1),
          target,
        ]);
      } catch (_) {
        // A player created before the Mix was turned on has no such filter.
      }
    }
  }

  Future<void> _writeAndroid(AudioPlayer player, MixBands bands) async {
    final equalizer = equalizerOf(player);
    if (equalizer == null) return;
    final parameters = _parameters[equalizer] ??= await equalizer.parameters
        .timeout(const Duration(seconds: 3));
    final flat = bands == mixFlat;
    final saved = equalizerBandGains.value;
    final userOn = equalizerEnabled.value;
    for (var i = 0; i < parameters.bands.length; i++) {
      final band = parameters.bands[i];
      final hertz = band.centerFrequency;
      final move = hertz < 300
          ? bands.low
          : hertz < 4000
          ? bands.mid
          : bands.high;
      // The user's own band when their equalizer is on, or when the Mix is
      // done and hands the equalizer back as it was.
      final own = (userOn || flat) && i < saved.length ? saved[i] : 0.0;
      await band.setGain(
        (own + move).clamp(parameters.minDecibels, parameters.maxDecibels),
      );
    }
    await equalizer.setEnabled(userOn || !flat);
  }
}
