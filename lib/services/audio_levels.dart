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
import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:just_audio_media_kit/mediakit_player.dart';
import 'package:musify/main.dart';
import 'package:musify/utilities/platform_utils.dart';

/// What is playing right now, each from 0 to 1: how loud, how much a beat or
/// a new note just hit (onset) and how bright (treble against bass).
typedef AudioLevel = ({double loud, double onset, double bright});

/// Live levels of the audio Zenify plays, for the player's waves.
///
/// Desktop reads them from filters in libmpv, which plays the audio anyway.
/// Android reads them from its Visualizer, which needs the audio recording
/// permission, so phones only use it once the user allows it.
class AudioLevels {
  AudioLevels._();

  static const _methods = MethodChannel('zenify/audio_levels');
  static const _frames = EventChannel('zenify/audio_levels/frames');

  /// mpv's label for the filters; their numbers land in `af-metadata/zviz`.
  /// They join mpv's filter chain beside media_kit's own (scaletempo for the
  /// speed) and leave it when the waves stop listening.
  static const _label = 'zviz';
  static const _spectralFilter =
      '@$_label:lavfi=[astats=metadata=1:reset=1:measure_perchannel=none:'
      'measure_overall=RMS_level,aspectralstats=win_size=1024:'
      'measure=centroid+flux]';
  // libmpv builds without aspectralstats (FFmpeg before 5.1) still have astats.
  static const _loudnessFilter =
      '@$_label:lavfi=[astats=metadata=1:reset=1:measure_perchannel=none:'
      'measure_overall=RMS_level]';

  /// Whether levels can be read without asking the user anything.
  static Future<bool> get available async {
    if (isDesktopPlatform) return MediaKitPlayer.latest != null;
    if (!isAndroidPlatform) return false;
    try {
      return await _methods.invokeMethod<bool>('hasPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Whether this platform can read levels once the user allows it.
  static bool get canAsk => isAndroidPlatform;

  /// Asks for the audio recording permission (Android); true once granted.
  static Future<bool> requestAccess() async {
    try {
      return await _methods.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static StreamController<AudioLevel>? _levels;

  /// Levels while listened to; check [available] first. Every listener (the
  /// player and the mini player) shares one reader, which stops with the last.
  static Stream<AudioLevel> listen() {
    StreamSubscription<(double, double, double)>? source;
    return (_levels ??= StreamController.broadcast(
      onListen: () {
        final normalizer = _Normalizer();
        source = (isDesktopPlatform ? _mpvFrames() : _androidFrames()).listen(
          (frame) => _levels?.add(normalizer(frame)),
        );
      },
      onCancel: () => source?.cancel(),
    )).stream;
  }

  /// (energy, flux, spectral centroid in Hz) from Android's Visualizer.
  static Stream<(double, double, double)> _androidFrames() {
    final session = audioHandler.audioPlayer.androidAudioSessionId ?? 0;
    return _frames
        .receiveBroadcastStream(session)
        .map((event) {
          final values = (event as List).cast<num>();
          return (
            values[0].toDouble(),
            values[1].toDouble(),
            values[2].toDouble(),
          );
        })
        // A failed Visualizer ends the stream; the waves keep their own motion.
        .handleError((Object _) {});
  }

  /// The same from mpv's audio filters, polled at about the rate they update
  /// while something plays.
  static Stream<(double, double, double)> _mpvFrames() {
    Timer? timer;
    late final StreamController<(double, double, double)> controller;
    var last = '';
    var lastEnergy = 0.0;
    var frames = 0;
    var silentPolls = 0;
    var filter = _spectralFilter;
    var polling = false;

    Future<void> attach(MediaKitPlayer player) async {
      await player.mpvCommand(['af', 'remove', '@$_label']);
      await player.mpvCommand(['af', 'add', filter]);
    }

    Future<void> poll(MediaKitPlayer player) async {
      final text = await player.getMpvProperty('af-metadata/$_label');
      // A filter just (re)started reports '{}' until its first frame.
      final hasFrame = text.contains('lavfi.');
      if (!hasFrame && ++silentPolls % 40 == 0) {
        // Nothing for a second of playback: media_kit replaced the chain
        // (a speed change does), or mpv dropped a filter that failed to
        // start, which without any frame yet means aspectralstats.
        if (frames == 0) filter = _loudnessFilter;
        await attach(player);
      }
      if (frames >= 20 &&
          filter == _spectralFilter &&
          !last.contains('aspectralstats')) {
        filter = _loudnessFilter;
        await attach(player);
      }
      if (!hasFrame || text == last) return;
      silentPolls = 0;
      last = text;
      frames++;
      final Map<String, dynamic> values;
      try {
        values = jsonDecode(text) as Map<String, dynamic>;
      } on FormatException {
        return;
      }
      double? read(String key) => double.tryParse('${values[key] ?? ''}');
      final db = read('lavfi.astats.Overall.RMS_level') ?? -120;
      final energy = db.isFinite ? pow(10, db / 20).toDouble() : 0.0;
      final flux =
          read('lavfi.aspectralstats.1.flux') ??
          max(0, energy - lastEnergy).toDouble();
      lastEnergy = energy;
      controller.add((
        energy,
        flux,
        read('lavfi.aspectralstats.1.centroid') ?? 0,
      ));
    }

    MediaKitPlayer? player;
    controller = StreamController(
      onListen: () async {
        final current = player = MediaKitPlayer.latest;
        if (current == null) return;
        await attach(current);
        timer = Timer.periodic(const Duration(milliseconds: 25), (_) async {
          if (polling ||
              controller.isClosed ||
              !audioHandler.playbackState.value.playing) {
            return;
          }
          polling = true;
          try {
            await poll(current);
          } finally {
            polling = false;
          }
        });
      },
      onCancel: () async {
        timer?.cancel();
        await player?.mpvCommand(['af', 'remove', '@$_label']);
      },
    );
    return controller.stream;
  }
}

/// Turns raw frames into 0–1 levels that suit any song: each measure is
/// divided by its recent peak, which decays so quiet songs still move.
class _Normalizer {
  double _energyPeak = 1e-4;
  double _fluxPeak = 1e-4;
  double _fluxAverage = 0;

  AudioLevel call((double, double, double) frame) {
    final (energy, flux, centroid) = frame;
    _energyPeak = max(energy, _energyPeak * 0.997);
    _fluxPeak = max(flux, _fluxPeak * 0.99);
    _fluxAverage += (flux - _fluxAverage) * 0.1;
    // A beat stands out from the flux around it.
    final onset = ((flux - _fluxAverage) / max(_fluxPeak - _fluxAverage, 1e-6))
        .clamp(0.0, 1.0);
    final bright = centroid <= 0
        ? 0.5
        : (log(centroid / 150) / log(6000 / 150)).clamp(0.0, 1.0);
    return (
      loud: sqrt((energy / _energyPeak).clamp(0.0, 1.0)),
      onset: sqrt(onset),
      bright: bright,
    );
  }
}
