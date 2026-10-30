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

import 'package:flutter/widgets.dart'
    show AppLifecycleListener, AppLifecycleState, WidgetsBinding;
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:just_audio_media_kit/mediakit_player.dart';
import 'package:musify/main.dart';
import 'package:musify/utilities/platform_utils.dart';

/// What is playing right now, each from 0 to 1: how loud, how much a beat
/// just hit (onset), and the level of each of [AudioLevels.bandCount]
/// frequency bands, from sub-bass to treble.
typedef AudioLevel = ({double loud, double onset, List<double> bands});

/// A raw reading: the overall amplitude and each band's, linear.
typedef _Frame = ({double loud, List<double> bands});

/// Live levels of the audio Zenify plays, for the player's waves.
///
/// Desktop reads them from filters in libmpv, which plays the audio anyway.
/// Phones use a lightweight animation instead, with no audio capture or
/// recording permission. The desktop reader runs only while listened to and
/// while the app is visible.
class AudioLevels {
  AudioLevels._();

  static const bandCount = 5;

  /// mpv's label for the filters; their numbers land in `af-metadata/zviz`.
  /// They are installed at engine preparation and retained until disposal.
  /// The widgets only poll their metadata while visible.
  static const _label = 'zviz';
  static const _mono = 'pan=mono|c0=0.5*c0+0.5*c1';

  /// Five mono copies of the sound through a low-pass, three band-passes and
  /// a high-pass become extra channels for astats to measure; the last pan
  /// drops them again, so what plays is unchanged. Simple filters, cheaper
  /// than an FFT.
  static const _bandsFilter =
      '@$_label:lavfi=[aformat=channel_layouts=stereo,'
      'asplit=6[o][a][b][c][d][e];'
      '[a]$_mono,lowpass=f=90[A];'
      '[b]$_mono,bandpass=f=180:width_type=o:w=1.2[B];'
      '[c]$_mono,bandpass=f=600:width_type=o:w=1.5[C];'
      '[d]$_mono,bandpass=f=2000:width_type=o:w=1.5[D];'
      '[e]$_mono,highpass=f=6000[E];'
      '[o][A][B][C][D][E]amerge=inputs=6,'
      'astats=metadata=1:reset=1:measure_overall=none:'
      'measure_perchannel=RMS_level,'
      'pan=stereo|c0=c0|c1=c1]';

  /// Prepare analysis before any desktop source is opened. Opening/closing
  /// a visualizer must never add/remove filters on a playing output device.
  static void configureDesktop() {
    JustAudioMediaKit.audioFilters = const [_bandsFilter];
    // Zenify uses speed, not independent pitch control. Native mpv speed
    // preserves the analysis chain; media_kit's pitch mode replaces `af`.
    JustAudioMediaKit.pitch = false;
  }

  /// Phones never open an audio reader.
  static Future<bool> get available async =>
      isDesktopPlatform && MediaKitPlayer.latest != null;

  static StreamController<AudioLevel>? _levels;

  /// Levels while listened to; check [available] first. Every listener (the
  /// player and the mini player) shares one reader, which stops with the
  /// last one and while the app is out of view.
  static Stream<AudioLevel> listen() {
    if (!isDesktopPlatform) return const Stream.empty();
    StreamSubscription<_Frame>? source;
    AppLifecycleListener? lifecycle;

    var listening = false;
    var visible = true;
    var transition = Future<void>.value();

    // Finish releasing the old reader before attaching another, including
    // after a surface remount.
    void update() {
      transition = transition.then((_) async {
        if (!listening || !visible) {
          await source?.cancel();
          source = null;
        } else if (source == null) {
          var normalizer = _Normalizer();
          String? track;
          source = _mpvFrames().listen((frame) {
            final current = audioHandler.mediaItem.valueOrNull?.id;
            if (current != track) {
              track = current;
              normalizer = _Normalizer();
            }
            _levels?.add(normalizer(frame));
          });
        }
      });
    }

    return (_levels ??= StreamController.broadcast(
      onListen: () {
        listening = true;
        final state = WidgetsBinding.instance.lifecycleState;
        visible =
            state != AppLifecycleState.hidden &&
            state != AppLifecycleState.paused &&
            state != AppLifecycleState.detached;
        lifecycle = AppLifecycleListener(
          onStateChange: (state) {
            visible =
                state != AppLifecycleState.hidden &&
                state != AppLifecycleState.paused &&
                state != AppLifecycleState.detached;
            update();
          },
        );
        update();
      },
      onCancel: () {
        lifecycle?.dispose();
        lifecycle = null;
        listening = false;
        update();
      },
    )).stream;
  }

  /// Read only: filter ownership belongs to the engine, not either widget.
  /// Rebinding on every poll also follows native player replacements.
  static Stream<_Frame> _mpvFrames() {
    Timer? timer;
    late final StreamController<_Frame> controller;
    var polling = false;
    var cancelled = false;

    double amplitude(Map<String, dynamic> values, String key) {
      final db = double.tryParse('${values[key] ?? ''}') ?? -120;
      return db.isFinite ? pow(10, db / 20).toDouble() : 0;
    }

    Future<void> poll() async {
      if (polling || cancelled || !audioHandler.playbackState.value.playing)
        return;
      final player = MediaKitPlayer.latest;
      if (player == null) return;
      polling = true;
      try {
        final text = await player.getMpvProperty('af-metadata/$_label');
        if (cancelled || !text.contains('lavfi.')) return;
        final values = jsonDecode(text) as Map<String, dynamic>;
        controller.add((
          loud:
              (amplitude(values, 'lavfi.astats.1.RMS_level') +
                  amplitude(values, 'lavfi.astats.2.RMS_level')) /
              2,
          bands: [
            for (var channel = 3; channel < 3 + bandCount; channel++)
              amplitude(values, 'lavfi.astats.$channel.RMS_level'),
          ],
        ));
      } catch (_) {
        // A source may release its engine while a read is pending. Retry
        // the current engine next time; never repair filters during playback.
      } finally {
        polling = false;
      }
    }

    controller = StreamController(
      onListen: () {
        timer = Timer.periodic(const Duration(milliseconds: 25), (_) {
          unawaited(poll());
        });
      },
      onCancel: () {
        cancelled = true;
        timer?.cancel();
      },
    );
    return controller.stream;
  }
}

/// Turns raw readings into 0–1 levels that suit any song: each band is
/// measured against its own recent peak, which decays, so quiet songs and
/// quiet treble still move; a band far below the song's loudness stays low.
/// A beat is the low bands rising above their recent average.
class _Normalizer {
  double _loudPeak = 1e-4;
  final _bandPeaks = List<double>.filled(AudioLevels.bandCount, 1e-4);
  double _lastLow = 0;
  double _riseAverage = 0;
  double _risePeak = 1e-4;

  AudioLevel call(_Frame frame) {
    _loudPeak = max(frame.loud, _loudPeak * 0.997);
    final bands = <double>[];
    for (var i = 0; i < AudioLevels.bandCount; i++) {
      final value = i < frame.bands.length ? frame.bands[i] : 0.0;
      _bandPeaks[i] = max(value, _bandPeaks[i] * 0.996);
      final relative = (value / _bandPeaks[i]).clamp(0.0, 1.0);
      final presence = (value / (_loudPeak * 0.02)).clamp(0.0, 1.0);
      bands.add(sqrt(relative) * presence);
    }

    final low = frame.bands.isEmpty
        ? frame.loud
        : frame.bands.take(2).fold<double>(0, (a, b) => a + b);
    final rise = max(0, low - _lastLow).toDouble();
    _lastLow = low;
    _risePeak = max(rise, _risePeak * 0.99);
    _riseAverage += (rise - _riseAverage) * 0.1;
    final onset = ((rise - _riseAverage) / max(_risePeak - _riseAverage, 1e-6))
        .clamp(0.0, 1.0);

    return (
      loud: sqrt((frame.loud / _loudPeak).clamp(0.0, 1.0)),
      onset: sqrt(onset),
      bands: bands,
    );
  }
}
