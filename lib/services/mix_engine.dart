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

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:musify/main.dart' show logger;
import 'package:musify/services/mix_transition.dart';
import 'package:musify/utilities/platform_utils.dart';
import 'package:rxdart/rxdart.dart';

/// A song loaded ahead of its turn: what plays it and where it came from.
typedef MixSource = ({Map song, AudioSource source, String url, bool offline});

/// The song the Mix would bring in over the end of the one playing.
typedef MixPlan = ({Map song, String entryId});

/// What a player's volume must be for [gain] (0 to 1) of amplitude. libmpv
/// plays the cube of its volume; ExoPlayer plays the volume itself.
double mixVolumeFor(double gain) =>
    isDesktopPlatform ? pow(gain, 1 / 3).toDouble() : gain;

/// The Mix: the next song starts on a second player while the one playing
/// ends on its own, their volumes crossing.
///
/// The player that plays the current song is [active]. When a transition
/// starts the two swap: the one coming in becomes [active] at once, and the
/// one going out is left as a tail that fades and stops. Without a transition
/// the second player is never created.
class MixEngine {
  MixEngine({
    required AudioPlayer first,
    required this.createPlayer,
    required this.plan,
    required this.cue,
    required this.resolve,
    required this.prepared,
    required this.advance,
    required this.userVolume,
    required this.applyVolume,
    required this.setBands,
    this.bandsLead = Duration.zero,
  }) : _active = first,
       _activeSubject = BehaviorSubject.seeded(first);

  static const tick = Duration(milliseconds: 50);

  /// How long before the transition the next song is loaded.
  static const _prepareAhead = Duration(seconds: 20);

  /// How near its start a transition is timed to the millisecond.
  static const _aim = Duration(milliseconds: 400);

  /// How long a player takes to sound after it is told to play: learned from
  /// each transition, so the next one lands on the beat.
  Duration _latency = const Duration(milliseconds: 25);
  Timer? _due;
  Timer? _tempoReturn;
  double? _baseSpeed;
  int _ticks = 0;
  int _late = 0;

  /// A transition with less of the song left than this is not worth starting.
  static const _shortest = Duration(milliseconds: 300);

  /// Builds the second player, as the first one was built.
  final AudioPlayer Function() createPlayer;

  /// The song to bring in next; null when this song ends with no transition.
  final MixPlan? Function() plan;

  /// Where and how the playing song gives way to the next.
  final MixCue Function(MixPlan next, Duration duration) cue;

  /// Finds where a song plays from; null when it cannot play now.
  final Future<MixSource?> Function(Map song) resolve;

  /// Called with the second player once the next song is loaded in it.
  final Future<void> Function(AudioPlayer player, Map song) prepared;

  /// Moves the queue on to the song that just came in.
  final Future<void> Function() advance;

  /// The volume the user chose, from 0 to 1.
  final double Function() userVolume;

  /// Puts the user's volume and [gain] to the active player.
  final Future<void> Function() applyVolume;

  /// Puts the level of its bass, mids and treble to a player.
  final void Function(AudioPlayer player, MixBands bands) setBands;

  /// How much later than the volume the bands are heard: they are sent
  /// that much ahead.
  final Duration bandsLead;

  /// The bands [cue] has at [t], sent [bandsLead] ahead.
  MixFrame _bandsAt(MixCue cue, double t) => cue.frame(
    min(1, t + bandsLead.inMicroseconds / max(1, cue.length.inMicroseconds)),
  );

  AudioPlayer _active;
  AudioPlayer? _other;
  final BehaviorSubject<AudioPlayer> _activeSubject;

  AudioPlayer get active => _active;
  double get userSpeed => _baseSpeed ?? _active.speed;

  /// The active player, and each one that takes its place.
  Stream<AudioPlayer> get activeStream => _activeSubject.stream;

  /// The second player, once a transition needed it.
  AudioPlayer? get other => _other;

  /// The part (0 to 1) of its volume the active player has: under 1 only
  /// while it comes in.
  double gain = 1;

  /// Where the song playing starts to give way to the next; null when it
  /// ends with no transition, or that is not known yet.
  final outStart = ValueNotifier<Duration?>(null);

  /// Whether a song is going out under the active one.
  bool get fading => _tail != null;

  ({String entryId, MixSource source, MixCue cue})? _prepared;

  /// The song has to play this long before its transition is worked out.
  static const _settle = Duration(seconds: 6);
  String? _preparingId;
  String? _failedId;
  int _generation = 0;

  AudioPlayer? _tail;
  Duration _tailStart = Duration.zero;
  MixCue? _cue;
  Timer? _timer;
  bool _writing = false;
  Future<void> _stopped = Future.value();
  Completer<void>? _previewDone;
  MixPlan? _previewPlan;
  MixCue? _previewCue;
  void Function(Map)? _previewSong;
  bool _previewReady = false;
  bool _starting = false;
  Future<void> _loads = Future.value();

  /// Audition through these same two decks, without advancing the queue.
  /// The handler pauses and restores its source around this operation.
  Future<void> preview(
    Map song,
    Map next,
    MixCue cue, {
    required void Function(Map) onSong,
    Duration? startAt,
  }) async {
    cancel();
    final done = _previewDone = Completer<void>();
    _previewSong = onSong;
    _previewPlan = (song: next, entryId: 'mix-preview');
    _previewCue = cue;
    _previewReady = false;
    try {
      await Future.any([_loads, done.future]);
      if (done.isCompleted) return;
      await Future.any([_stopped, done.future]);
      if (done.isCompleted) return;
      final source = await Future.any<MixSource?>([
        resolve(song).timeout(const Duration(seconds: 30)),
        done.future.then((_) => null),
      ]);
      if (done.isCompleted) return;
      // Clipped sources have a different timeline from the editor.
      if (source == null ||
          // ignore: deprecated_member_use
          source.source is ConcatenatingAudioSource ||
          source.source is ClippingAudioSource) {
        throw StateError('Mix preview source unavailable');
      }
      await _active.setVolume(0);
      final loading = _active
          .setAudioSource(
            source.source,
            initialPosition:
                startAt ??
                (cue.outStart > const Duration(seconds: 5)
                    ? cue.outStart - const Duration(seconds: 5)
                    : Duration.zero),
          )
          .timeout(const Duration(seconds: 30));
      await Future.any([loading, done.future]);
      if (done.isCompleted) {
        // Dispose the platform load before restoring the previous source.
        // just_audio's activation token rejects any late load completion.
        await _active.stop();
        return;
      }
      await prepared(_active, song);
      await Future.any([_prepare(_previewPlan!, cue), done.future]);
      if (done.isCompleted) return;
      if (_prepared == null)
        throw StateError('Mix preview could not prepare the pair');
      onSong(song);
      _previewReady = true;
      await applyVolume();
      unawaited(
        _active.play().catchError((Object e, StackTrace s) {
          if (!done.isCompleted) done.completeError(e, s);
        }),
      );
      // Also bounds a stalled network source that never advances its clock.
      await done.future.timeout(const Duration(seconds: 90));
    } finally {
      _previewReady = false;
      _previewDone = null;
      _previewPlan = null;
      _previewCue = null;
      _previewSong = null;
      cancel();
      await _active.pause();
      await _stopped;
    }
  }

  void stopPreview() {
    final done = _previewDone;
    if (done != null && !done.isCompleted) done.complete();
    cancel();
  }

  /// Edits made while the next song was preloaded must replace that preload.
  void refresh() {
    if (fading || _previewDone != null) return;
    _discardPrepared();
    _failedId = null;
    update();
  }

  /// Follows the song playing: loads the next one when its turn is near and
  /// starts the transition when the time comes. Cheap; called at every
  /// position update.
  void update() {
    if (_starting) return;
    if (_previewDone != null && !_previewReady) return;
    if (fading) return;
    final next = _previewPlan ?? plan();
    if (next == null || next.entryId == _failedId) {
      outStart.value = null;
      _discardPrepared();
      return;
    }
    if (_prepared != null && _prepared!.entryId != next.entryId) {
      _discardPrepared();
    }
    final duration = _active.duration;
    if (duration == null || duration <= Duration.zero) return;
    final position = _active.position;
    // Once the next song is loaded its transition is settled.
    final cue = _prepared?.cue ?? _previewCue ?? this.cue(next, duration);
    // Let startup settle on long songs, but never miss an early manual cue
    // (or a transition in a short song) just to wait six seconds.
    if (_previewDone == null &&
        position < _settle &&
        cue.outStart > _prepareAhead + _settle)
      return;
    outStart.value = cue.outStart;
    if (position < cue.outStart - _prepareAhead) return;

    if (_prepared == null) {
      if (_preparingId != next.entryId) unawaited(_prepare(next, cue));
      return;
    }
    final left = cue.outStart - position;
    if (left > _aim || _due != null || duration - position < _shortest) return;
    if (!_active.playing || _active.processingState != ProcessingState.ready) {
      return;
    }
    // Position updates are too far apart to start on a beat: a timer does.
    final wait = left * (1 / _active.speed) - _latency;
    _due = Timer(wait.isNegative ? Duration.zero : wait, () {
      _due = null;
      final now = _active.position;
      if (fading || _prepared?.cue != cue || !_active.playing) return;
      if ((_previewPlan ?? plan())?.entryId != _prepared?.entryId) {
        _discardPrepared();
        return;
      }
      if ((cue.outStart - now).abs() > _aim * 2 && now < cue.outStart) return;
      unawaited(_start(now, cue).catchError(_logError));
    });
  }

  /// The loaded song with this queue entry, when it is the one coming in:
  /// the queue then plays it as it is instead of loading it again.
  MixSource? adopt(String? entryId) {
    final prepared = _prepared;
    if (!fading || prepared == null || prepared.entryId != entryId) return null;
    _prepared = null;
    return prepared.source;
  }

  /// Drops a transition in course and any song loaded ahead: another song
  /// was asked for, or playback stopped.
  void cancel() {
    _resetTempo();
    _generation++;
    _preparingId = null;
    _failedId = null;
    outStart.value = null;
    if (fading) {
      _due?.cancel();
      _due = null;
      _prepared = null;
      _finish();
    } else {
      _discardPrepared();
    }
  }

  /// Ends the tail at once: the user moved within the song that came in.
  void cutTail() {
    _due?.cancel();
    _due = null;
    if (fading) _finish();
  }

  /// A paused song pauses the one going out with it.
  void pause() {
    final tail = _tail;
    if (tail != null) unawaited(tail.pause().catchError(_logError));
  }

  void resume() {
    final tail = _tail;
    if (tail != null) unawaited(tail.play().catchError(_logError));
  }

  /// A tempo change reaches both decks, including a song prepared but not
  /// playing yet. Recompute the deadline from the new playback rate.
  Future<void> setSpeed(double speed) async {
    _tempoReturn?.cancel();
    if (_baseSpeed != null) _baseSpeed = speed;
    _due?.cancel();
    _due = null;
    await Future.wait([
      _active.setSpeed(speed * (_cue?.tempoRatio ?? 1)),
      if (_other != null) _other!.setSpeed(speed),
    ]);
    update();
  }

  Future<void> dispose() async {
    cancel();
    await _other?.dispose();
    await _activeSubject.close();
  }

  void _discardPrepared() {
    _due?.cancel();
    _due = null;
    if (_prepared == null && _preparingId == null) return;
    _generation++;
    _preparingId = null;
    if (_prepared != null) {
      _prepared = null;
      final other = _other;
      if (other != null) _stop(other);
    }
  }

  /// Stops [player]; it is loaded again only once this has finished.
  void _stop(AudioPlayer player) {
    final before = _stopped;
    _stopped = () async {
      await before;
      await player.stop().catchError(_logError);
    }();
  }

  Future<void> _prepare(MixPlan next, MixCue cue) {
    final generation = ++_generation;
    _preparingId = next.entryId;
    return _loads = _loads.then((_) => _load(next, cue, generation));
  }

  Future<void> _load(MixPlan next, MixCue cue, int generation) async {
    try {
      if (generation != _generation) return;
      final source = await resolve(next.song)
          .timeout(const Duration(seconds: 30));
      if (generation != _generation) return;
      // SponsorBlock's clips have positions of their own: no transition.
      if (source == null ||
          // ignore: deprecated_member_use
          source.source is ConcatenatingAudioSource ||
          source.source is ClippingAudioSource) {
        _failedId = next.entryId;
        return;
      }
      await _stopped;
      if (generation != _generation) return;
      final player = _other ??= createPlayer();
      await player.setVolume(0);
      await player.setLoopMode(LoopMode.off);
      await player.setSpeed(_active.speed);
      await player
          .setAudioSource(source.source, initialPosition: cue.inStart)
          .timeout(const Duration(seconds: 30));
      if (generation != _generation) {
        _stop(player);
        return;
      }
      await prepared(player, next.song);
      if (generation != _generation) return;
      _prepared = (entryId: next.entryId, source: source, cue: cue);
    } catch (e, stackTrace) {
      logger.log(
        'Mix: preparing the next song failed',
        error: e,
        stackTrace: stackTrace,
      );
      if (generation == _generation) _failedId = next.entryId;
    } finally {
      if (generation == _generation) _preparingId = null;
    }
  }

  Future<void> _start(Duration position, MixCue cue) async {
    _starting = true;
    try {
      final generation = _generation;
      final tail = _active;
      final coming = _other!;
      // A seek into the transition must enter both recordings at the same
      // progress, rather than restart the fade at full outgoing volume.
      final elapsed = position > cue.outStart
          ? position - cue.outStart
          : Duration.zero;
      if (elapsed >= cue.length - _shortest) return;
      if (elapsed > const Duration(milliseconds: 150)) {
        await coming.seek(cue.inStart + elapsed * cue.tempoRatio);
        if (generation != _generation || !tail.playing) return;
      }
      final speed = userSpeed;
      _tempoReturn?.cancel();
      if (_baseSpeed != null) await tail.setSpeed(speed);
      _baseSpeed = speed;
      await coming.setSpeed(speed * cue.tempoRatio);
      if (generation != _generation) return;
      _tail = tail;
      _tailStart = cue.outStart;
      _cue = cue;
      outStart.value = null;
      logger.log(
        'Mix: ${cue.style.name}, ${cue.length.inMilliseconds} ms, '
        'out at ${cue.outStart.inMilliseconds} (${position.inMilliseconds}), '
        'in at ${cue.inStart.inMilliseconds}, lead ${_latency.inMilliseconds}',
      );
      _other = tail;
      _active = coming;
      // The new song starts as the first frame says, before it sounds.
      final frame = cue.frame(
        elapsed.inMicroseconds / cue.length.inMicroseconds,
      );
      gain = frame.inGain;
      final bands = _bandsAt(
        cue,
        elapsed.inMicroseconds / cue.length.inMicroseconds,
      );
      setBands(coming, bands.inBands);
      setBands(tail, bands.outBands);
      _activeSubject.add(coming);
      _ticks = 0;
      _late = 0;
      _timer = Timer.periodic(tick, (_) => _step());
      if (_previewDone != null) {
        _prepared = null;
        _previewSong?.call(_previewPlan!.song);
        unawaited(
          applyVolume().then((_) => coming.play()).catchError(_logError),
        );
      } else {
        unawaited(advance().catchError(_logError));
      }
    } finally {
      _starting = false;
    }
  }

  /// How far the transition is, from 0 to 1. Both songs tell it, so one that
  /// stalls or ends does not hold the other.
  double get _progress {
    final cue = _cue!;
    final whole = cue.length.inMicroseconds;
    if (whole <= 0) return 1;
    final out = (_tail!.position - _tailStart).inMicroseconds / whole;
    final into =
        (_active.position - cue.inStart).inMicroseconds /
        (whole * cue.tempoRatio);
    return max(out, into).clamp(0.0, 1.0);
  }

  void _step() {
    final tail = _tail;
    if (tail == null) return;
    final t = _progress;
    if (t >= 1) {
      _finish();
      return;
    }
    _learnLatency(tail);
    final frame = _cue!.frame(t);
    gain = frame.inGain;
    final bands = _bandsAt(_cue!, t);
    setBands(_active, bands.inBands);
    setBands(tail, bands.outBands);
    if (_writing) return;
    _writing = true;
    Future.wait([
          applyVolume(),
          tail.setVolume(userVolume() * mixVolumeFor(frame.outGain)),
        ])
        .catchError((Object e, StackTrace stackTrace) {
          _logError(e, stackTrace);
          return const <void>[];
        })
        .whenComplete(() => _writing = false);
  }

  /// Half a second in, how far the new song runs behind the old one says
  /// how late it started.
  void _learnLatency(AudioPlayer tail) {
    final cue = _cue!;
    _ticks++;
    if (_ticks < 8 || _ticks > 15 || !tail.playing || !_active.playing) return;
    final behind =
        (tail.position - cue.outStart) -
        (_active.position - cue.inStart) * (1 / cue.tempoRatio);
    _late += behind.inMicroseconds;
    if (_ticks < 15) return;
    final learned = _latency + Duration(microseconds: _late ~/ 8) * 0.7;
    _latency = Duration(microseconds: learned.inMicroseconds.clamp(0, 250000));
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
    final tail = _tail;
    _tail = null;
    _cue = null;
    _returnTempo();
    gain = 1;
    setBands(_active, mixFlat);
    unawaited(applyVolume().catchError(_logError));
    if (tail != null) {
      setBands(tail, mixFlat);
      _stop(tail);
    }
    final done = _previewDone;
    if (done != null && !done.isCompleted) done.complete();
  }

  void _resetTempo() {
    _tempoReturn?.cancel();
    _tempoReturn = null;
    final speed = _baseSpeed;
    _baseSpeed = null;
    if (speed != null) unawaited(_active.setSpeed(speed).catchError(_logError));
  }

  void _returnTempo() {
    final speed = _baseSpeed;
    if (speed == null || (_active.speed - speed).abs() < 0.0001) {
      _baseSpeed = null;
      return;
    }
    final player = _active;
    final from = player.speed;
    var ticks = 0;
    _tempoReturn?.cancel();
    _tempoReturn = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!player.playing) return;
      ticks++;
      final t = (ticks / 80).clamp(0.0, 1.0);
      unawaited(
        player.setSpeed(from + (speed - from) * t).catchError(_logError),
      );
      if (t == 1) {
        _tempoReturn?.cancel();
        _baseSpeed = null;
      }
    });
  }

  void _logError(Object e, StackTrace stackTrace) =>
      logger.log('Mix: player error', error: e, stackTrace: stackTrace);
}
