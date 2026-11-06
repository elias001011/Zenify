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

/// The lengths of the fade between songs the user can choose, in seconds;
/// 0 is off.
const songFadeChoices = [0, 2, 4, 6, 8, 10, 12];

/// How long the fade at each end of a song lasts: [seconds], or a third of
/// the song when it is shorter than three times that. [duration] is null
/// while it is unknown.
Duration songFadeLength(Duration? duration, int seconds) {
  final full = Duration(seconds: seconds);
  return duration == null || duration >= full * 3 ? full : duration ~/ 3;
}

/// The multiplier (0 to 1) of the volume at [position] of a song: it rises
/// over the first seconds when [fadeIn] and falls over the last ones when
/// [fadeOut]. It depends on the position alone, so pausing, seeking and
/// resuming need no bookkeeping.
double songFadeGain({
  required Duration position,
  required Duration? duration,
  required int seconds,
  required bool fadeIn,
  required bool fadeOut,
}) {
  if (seconds <= 0 || (!fadeIn && !fadeOut)) return 1;
  final length = songFadeLength(duration, seconds);
  if (length <= Duration.zero) return 1;
  var gain = 1.0;
  if (fadeIn && position < length) {
    gain *= sin(_fraction(position, length) * pi / 2);
  }
  if (fadeOut && duration != null) {
    final into = position - (duration - length);
    if (into > Duration.zero) gain *= cos(_fraction(into, length) * pi / 2);
  }
  return gain;
}

double _fraction(Duration part, Duration whole) =>
    (part.inMicroseconds / whole.inMicroseconds).clamp(0.0, 1.0);

/// What the fade needs to know about the song playing.
typedef SongFadeState = ({
  Duration position,
  Duration? duration,
  int seconds,
  bool fadeOut,
  bool playing,
});

/// Keeps the [gain] of the fade between songs up to date. Inside a fade zone
/// of a song that plays it runs a fast timer, as the position updates are too
/// coarse for a smooth fade; elsewhere nothing runs.
class SongFade {
  SongFade({required this.read, required this.write});

  /// The state of the song, read at every update.
  final SongFadeState Function() read;

  /// Puts [gain] to the player's volume.
  final Future<void> Function() write;

  static const tick = Duration(milliseconds: 50);

  double gain = 1;

  /// The song playing began by an automatic advance: its start fades in, once.
  bool fadeIn = false;

  Timer? _timer;

  /// Works out the gain of the song's position now and writes it when it
  /// changed; completes when the write has.
  Future<void> update() {
    final state = read();
    if (fadeIn &&
        state.position >= songFadeLength(state.duration, state.seconds)) {
      fadeIn = false;
    }
    final next = songFadeGain(
      position: state.position,
      duration: state.duration,
      seconds: state.seconds,
      fadeIn: fadeIn,
      fadeOut: state.fadeOut,
    );
    if (state.playing && next < 1) {
      _timer ??= Timer.periodic(tick, (_) => unawaited(update()));
    } else {
      cancel();
    }
    if (next == gain) return Future.value();
    gain = next;
    return write();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
