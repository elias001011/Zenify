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
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive_ce/hive_ce.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/mediakit_player.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/services/mix_playlists.dart';
import 'package:musify/services/mix_transition.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/platform_utils.dart';

/// Turns the bass, mids and treble of each player down and up for the Mix.
///
/// Desktop: three filters in libmpv, untouched at 0 dB, moved by commands.
/// Android: the player's own equalizer, on top of the bands the user set.
class MixEffects {
  MixEffects({required this.equalizerOf});

  /// The filters a desktop player gets while some playlist plays with the Mix.
  /// At 0 dB each passes the sound as it is.
  static final desktopFilters = [
    '@zmixl:lavfi=[bass=g=0:f=200]',
    '@zmixm:lavfi=[equalizer=f=1000:t=o:w=2:g=0]',
    '@zmixh:lavfi=[treble=g=0:f=4000]',
    // Open at these cutoffs. Their mix option is never sent: mpv crashed.
    '@zmixhp:lavfi=[highpass=f=20]',
    '@zmixlp:lavfi=[lowpass=f=20000]',
    // Silent until used: the echo is tuned to each song's beat.
    '@zmixe:${_echoGraph(echoDefault)}',
  ];

  static const echoDefault = 500;

  /// One beat of [bpm], halved or doubled into a delay that sounds like an
  /// echo.
  static int echoDelay(double bpm) {
    var beat = 60000 / bpm;
    while (beat < 300) {
      beat *= 2;
    }
    while (beat > 800) {
      beat /= 2;
    }
    return beat.round();
  }

  /// The song, then three repeats of it, each quieter. The volume comes
  /// first: once the song is cut, only what came before it repeats.
  static String _echoGraph(int delay) =>
      'lavfi=[volume=1,asplit[d][w];'
      '[w]aecho=0:1:$delay|${delay * 2}|${delay * 3}:0.55|0.3|0.16[x];'
      '[d][x]amix=inputs=2:normalize=0:weights=1 0]';

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

  /// Whether the desktop players need the Mix's filters.
  static bool get mixFiltersWanted =>
      mixTransitions.value && mixPlaylists.value.isNotEmpty;

  /// What a desktop player has in its chain: the Mix's filters while it is in
  /// use and the user's bands while their equalizer is on. A filter that is
  /// not there costs nothing.
  static List<String> get desktopChain => [
    if (mixFiltersWanted) ...desktopFilters,
    if (equalizerEnabled.value) ...userFilters,
  ];

  static String _label(String filter) =>
      filter.substring(1, filter.indexOf(':'));

  Future<void> _queue = Future.value();

  Future<void> _enqueue(Future<void> Function() job) => _queue = _queue
      .then((_) => job())
      .catchError((Object e, StackTrace stackTrace) {
        logger.log(
          'Equalizer: desktop filters failed',
          error: e,
          stackTrace: stackTrace,
        );
      });

  Future<void> updateDesktopEq() => _enqueue(_setGains);

  /// Puts on each loaded desktop player the filters [desktopChain] asks for
  /// and takes off the others. Changing the chain interrupts the sound for a
  /// moment, so it is done only when a setting changes.
  Future<void> syncDesktopFilters() => _enqueue(() async {
    for (final entry in _mpv.entries.toList()) {
      final mpv = entry.value;
      if (mpv == null || entry.key.processingState == ProcessingState.idle) {
        continue;
      }
      final changed = await syncChain(mpv, desktopChain);
      if (changed) {
        _sent.remove(entry.key);
        _echo[entry.key] = echoDefault;
      }
    }
    await _setGains();
  });

  /// Puts [mpv]'s chain in line with [chain], leaving the other filters as
  /// they are; false when nothing had to change.
  @visibleForTesting
  static Future<bool> syncChain(MediaKitPlayer mpv, List<String> chain) async {
    final wanted = {for (final filter in chain) _label(filter)};
    final present = await mpv.getMpvProperty('af');
    var changed = false;
    for (final filter in [...desktopFilters, ...userFilters]) {
      final label = _label(filter);
      final has = RegExp('\\b$label\\b').hasMatch(present);
      if (has == wanted.contains(label)) continue;
      await mpv.mpvCommand(
        has ? ['af', 'remove', '@$label'] : ['af', 'add', filter],
      );
      changed = true;
    }
    return changed;
  }

  Future<void> _setGains() async {
    for (final entry in _mpv.entries.toList()) {
      final mpv = entry.value;
      if (mpv == null || entry.key.processingState == ProcessingState.idle) {
        continue;
      }
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
  final _echo = <AudioPlayer, int>{};

  /// Writes left in which every value is sent: mpv gives no error back for
  /// a command it could not apply, as while a song is being started.
  final _fresh = <AudioPlayer, int>{};

  /// Whether [player]'s echo repeats on the beat of a song at [bpm].
  bool echoFits(AudioPlayer player, double bpm) =>
      isDesktopPlatform && _echo[player] == echoDelay(bpm);

  /// Tunes the echo of [player] to [bpm]. Only for a player that is silent:
  /// changing the filter interrupts the sound for a moment.
  Future<void> tuneEcho(AudioPlayer player, double? bpm) async {
    final mpv = _mpv[player];
    if (!isDesktopPlatform || mpv == null || bpm == null || bpm <= 0) return;
    final delay = echoDelay(bpm);
    if (_echo[player] == delay) return;
    try {
      await mpv.mpvCommand(['af', 'remove', '@zmixe']);
      await mpv.mpvCommand(['af', 'add', '@zmixe:${_echoGraph(delay)}']);
      _echo[player] = delay;
      _sent.remove(player);
    } catch (e, stackTrace) {
      _echo.remove(player);
      logger.log(
        'Mix: tuning the echo failed',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// [player] just loaded a song: on desktop that may be a new libmpv, which
  /// starts with its bands untouched.
  void loaded(AudioPlayer player) {
    if (!isDesktopPlatform) return;
    final mpv = MediaKitPlayer.lastLoaded;
    if (_mpv[player] != mpv) {
      _mpv[player] = mpv;
      _sent.remove(player);
      _echo[player] = echoDefault;
    }
    // The same mpv may have been prepared under other settings.
    unawaited(syncDesktopFilters());
  }

  /// Puts [bands] to [player]. Calls may come faster than the player takes
  /// them: the newest wins.
  void write(AudioPlayer player, MixBands bands) {
    _wanted[player] = bands;
    if (!player.playing) {
      _fresh[player] = 10;
    } else if ((_fresh[player] ?? 0) > 0 || bands == mixFlat) {
      // Sent whole, even if nothing changed, until surely heard.
      _fresh[player] = (_fresh[player] ?? 1) - 1;
      _sent.remove(player);
      if (bands == mixFlat) {
        _sent[player] = _unknown;
        // Once more a moment later: a stuck echo or filter would last a song.
        Timer(const Duration(milliseconds: 500), () {
          if (_wanted[player] != mixFlat) return;
          _sent[player] = _unknown;
          if (_writing.add(player)) unawaited(_drain(player));
        });
      }
    }
    if (_writing.add(player)) unawaited(_drain(player));
  }

  /// Differs from any bands: everything is sent again.
  static const MixBands _unknown = (
    low: double.nan,
    mid: double.nan,
    high: double.nan,
    highPass: double.nan,
    lowPass: double.nan,
    dry: double.nan,
    echo: double.nan,
  );

  Future<void> _drain(AudioPlayer player) async {
    try {
      while (_wanted[player] != _sent[player]) {
        final bands = _wanted[player]!;
        final before = _sent[player] ?? _unknown;
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
    final commands = [
      if (before.low != bands.low) ('zmixl', 'gain', bands.low, 'bass'),
      if (before.mid != bands.mid) ('zmixm', 'gain', bands.mid, 'equalizer'),
      if (before.high != bands.high) ('zmixh', 'gain', bands.high, 'treble'),
      if (before.highPass != bands.highPass)
        ('zmixhp', 'f', max(bands.highPass, mixOpenLow), 'highpass'),
      if (before.lowPass != bands.lowPass)
        ('zmixlp', 'f', min(bands.lowPass, mixOpenHigh), 'lowpass'),
    ];
    final args = [
      for (final (label, command, value, target) in commands)
        [label, command, value.toStringAsFixed(command == 'f' ? 0 : 1), target],
      if (before.dry != bands.dry)
        ['zmixe', 'volume', bands.dry.toStringAsFixed(3), 'volume'],
      if (before.echo != bands.echo)
        ['zmixe', 'weights', '1 ${bands.echo.toStringAsFixed(3)}', 'amix'],
    ];
    for (final arg in args) {
      try {
        await mpv.mpvCommand(['af-command', ...arg]);
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
    final shelves = mixShelves(bands);
    final saved = equalizerBandGains.value;
    final userOn = equalizerEnabled.value;
    for (var i = 0; i < parameters.bands.length; i++) {
      final band = parameters.bands[i];
      final hertz = band.centerFrequency;
      final move = hertz < 300
          ? shelves.low
          : hertz < 4000
          ? shelves.mid
          : shelves.high;
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
