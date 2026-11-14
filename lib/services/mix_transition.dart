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

import 'dart:math';

/// How the volumes of the two songs move during a transition.
enum MixVolume {
  /// Equal power: one falls as the other rises, together as loud as one.
  crossfade,

  /// Both play in full for a while: the new one is up early, the old one
  /// leaves late. Meant to go with an [MixEq] that keeps them apart.
  overlap,

  /// The old one is gone by the middle, where the new one starts to rise.
  fadeOutIn,

  /// The old one ends as it was recorded; the new one rises under it.
  riseUnder,

  /// A hard swap in the middle.
  centerCut,

  /// The new song comes in whole a quarter of the way, on a beat; the old one
  /// is cut there and only its echo fades away.
  cutIn,
}

/// How the bass, mids and treble of the two songs trade places.
enum MixEq {
  none,

  /// The basses swap in the middle, so two bass lines never play together.
  bassSwapCenter,

  /// The basses swap near the end.
  bassSwapEnd,

  /// Treble first, then mids, then bass.
  threeBand,
}

/// A filter that moves over a song during the transition.
enum MixFilter {
  none,

  /// The old song thins out: its bass goes, then its mids.
  highPassOut,

  /// The new song starts muffled and opens up.
  lowPassIn,

  /// Both of the above.
  both,

  /// The old song is cut on a beat and leaves only its echo.
  echoOut,
}

/// One way of going from a song to the next.
enum MixStyle {
  /// A plain crossfade.
  smooth(MixVolume.crossfade, MixEq.none, MixFilter.none),

  /// One song fades away before the other rises.
  fadeOut(MixVolume.fadeOutIn, MixEq.none, MixFilter.none),

  /// A crossfade with the basses swapping in the middle.
  fade(MixVolume.crossfade, MixEq.bassSwapCenter, MixFilter.none),

  /// The new song opens up over the old one, the basses swapping at the end.
  rise(MixVolume.overlap, MixEq.bassSwapEnd, MixFilter.lowPassIn),

  /// Both in full, trading treble, mids and bass in turn.
  blend(MixVolume.overlap, MixEq.threeBand, MixFilter.none),

  /// Both in full, the new one muffled at first, basses swapping in the middle.
  wave(MixVolume.overlap, MixEq.bassSwapCenter, MixFilter.lowPassIn),

  /// The old song thins out as it fades: for songs that do not match.
  melt(MixVolume.crossfade, MixEq.bassSwapCenter, MixFilter.highPassOut),

  /// The new song rises under the recorded ending of the old one.
  under(MixVolume.riseUnder, MixEq.none, MixFilter.lowPassIn),

  /// The old song thins out, then a hard swap on the beat.
  slam(MixVolume.centerCut, MixEq.none, MixFilter.highPassOut),

  /// The old song is cut on a beat and echoes away under the new one.
  echo(MixVolume.cutIn, MixEq.none, MixFilter.echoOut),

  /// One filter closes the old song while another opens the new one.
  sweep(MixVolume.crossfade, MixEq.none, MixFilter.both);

  const MixStyle(this.volume, this.eq, this.filter);

  final MixVolume volume;
  final MixEq eq;
  final MixFilter filter;
}

/// What the Mix does to one song: its three bands in decibels (0 is
/// untouched), the cutoffs of a high-pass and a low-pass filter in hertz, and
/// the level (0 to 1) of the song itself and of its echo.
typedef MixBands = ({
  double low,
  double mid,
  double high,
  double highPass,
  double lowPass,
  double dry,
  double echo,
});

/// A high-pass at or under this lets everything through.
const double mixOpenLow = 20;

/// A low-pass at or over this lets everything through.
const double mixOpenHigh = 20000;

const MixBands mixFlat = (
  low: 0,
  mid: 0,
  high: 0,
  highPass: mixOpenLow,
  lowPass: mixOpenHigh,
  dry: 1,
  echo: 0,
);

/// [bands] with its filters turned into band cuts, for an equalizer that
/// has nothing else; the echo is left out.
MixBands mixShelves(MixBands bands) {
  double part(double from, double to, double value) =>
      (log(value / from) / log(to / from)).clamp(0.0, 1.0);
  final hp = max(bands.highPass, mixOpenLow);
  final lp = min(bands.lowPass, mixOpenHigh);
  return (
    low: min(bands.low, mixKill * part(mixOpenLow, 250, hp)),
    mid: min(
      bands.mid,
      min(mixKill / 2 * part(250, 1500, hp), mixKill / 3 * part(4000, 300, lp)),
    ),
    high: min(bands.high, mixKill * part(mixOpenHigh, 4000, lp)),
    highPass: mixOpenLow,
    lowPass: mixOpenHigh,
    dry: 1,
    echo: 0,
  );
}

/// A band this far down is as good as gone.
const double mixKill = -24;

/// A moment of a transition: the gain (0 to 1) and bands of the song going
/// out and of the one coming in.
typedef MixFrame = ({
  double outGain,
  double inGain,
  MixBands outBands,
  MixBands inBands,
});

/// Where and how a song gives way to the next: the outgoing position,
/// incoming position, duration and style.
class MixCue {
  const MixCue({
    required this.outStart,
    required this.inStart,
    required this.length,
    required this.style,
    this.volume,
    this.eq,
    this.filter,
    this.tempoRatio = 1,
  });
  final Duration outStart, inStart, length;
  final MixStyle style;
  final MixVolume? volume;
  final MixEq? eq;
  final MixFilter? filter;

  /// Incoming source seconds per outgoing source second during overlap.
  final double tempoRatio;
  bool get customized => volume != null || eq != null || filter != null;
  MixFrame frame(double t) =>
      mixFrame(style, t, volume: volume, eq: eq, filter: filter);
}

/// 0 before [from], 1 after [to], a smooth step in between.
double _ramp(double t, double from, double to) {
  if (t <= from) return 0;
  if (t >= to) return 1;
  final x = (t - from) / (to - from);
  return x * x * (3 - 2 * x);
}

/// The level of a band being traded, [x] of the way out: at equal power, so
/// the two songs' bands together stay as loud as one.
double _leaving(double x) => max(mixKill, 20 * log(cos(x * pi / 2)) / ln10);

/// The frame of [style] at [t], from 0 (the new song starts) to 1 (the old
/// one is gone).
MixFrame mixFrame(
  MixStyle style,
  double t, {
  MixVolume? volume,
  MixEq? eq,
  MixFilter? filter,
}) {
  t = t.clamp(0.0, 1.0);
  final double outGain;
  final double inGain;
  switch (volume ?? style.volume) {
    case MixVolume.crossfade:
      outGain = cos(t * pi / 2);
      inGain = sin(t * pi / 2);
    case MixVolume.overlap:
      outGain = cos(_ramp(t, 0.6, 1) * pi / 2);
      inGain = sin(_ramp(t, 0, 0.4) * pi / 2);
    case MixVolume.fadeOutIn:
      outGain = cos(_ramp(t, 0, 0.55) * pi / 2);
      inGain = sin(_ramp(t, 0.45, 1) * pi / 2);
    case MixVolume.riseUnder:
      outGain = cos(_ramp(t, 0.8, 1) * pi / 2);
      inGain = sin(t * pi / 2);
    case MixVolume.centerCut:
      outGain = 1 - _ramp(t, 0.48, 0.52);
      inGain = _ramp(t, 0.48, 0.52);
    case MixVolume.cutIn:
      outGain = cos(_ramp(t, 0.25, 1) * pi / 2);
      inGain = _ramp(t, 0.22, 0.25);
  }

  var outLow = 0.0, outMid = 0.0, outHigh = 0.0;
  var inLow = 0.0, inMid = 0.0, inHigh = 0.0;
  switch (eq ?? style.eq) {
    case MixEq.none:
      break;
    case MixEq.bassSwapCenter:
      outLow = _leaving(_ramp(t, 0.44, 0.56));
      inLow = _leaving(1 - _ramp(t, 0.44, 0.56));
    case MixEq.bassSwapEnd:
      outLow = _leaving(_ramp(t, 0.8, 0.92));
      inLow = _leaving(1 - _ramp(t, 0.8, 0.92));
    case MixEq.threeBand:
      outHigh = _leaving(_ramp(t, 0.15, 0.4));
      inHigh = _leaving(1 - _ramp(t, 0.15, 0.4));
      outMid = mixKill / 2 * _ramp(t, 0.4, 0.65);
      inMid = mixKill / 2 * (1 - _ramp(t, 0.4, 0.65));
      outLow = _leaving(_ramp(t, 0.65, 0.85));
      inLow = _leaving(1 - _ramp(t, 0.65, 0.85));
  }
  final chosen = filter ?? style.filter;
  var outHighPass = mixOpenLow, inLowPass = mixOpenHigh;
  var outDry = 1.0, outEcho = 0.0;
  if (chosen == MixFilter.highPassOut || chosen == MixFilter.both) {
    outHighPass = mixOpenLow * pow(75, _ramp(t, 0.05, 0.85));
  }
  if (chosen == MixFilter.lowPassIn || chosen == MixFilter.both) {
    final open = _ramp(t, 0, 0.7);
    inLowPass = open >= 1 ? mixOpenHigh : 300.0 * pow(mixOpenHigh / 300, open);
  }
  if (chosen == MixFilter.echoOut) {
    // The echo starts just before the cut, so it repeats the last beat.
    outEcho = 0.7 * _ramp(t, 0.18, 0.24);
    outDry = 1 - _ramp(t, 0.24, 0.25);
  }
  return (
    outGain: outGain,
    inGain: inGain,
    outBands: (
      low: outLow,
      mid: outMid,
      high: outHigh,
      highPass: outHighPass,
      lowPass: mixOpenHigh,
      dry: outDry,
      echo: outEcho,
    ),
    inBands: (
      low: inLow,
      mid: inMid,
      high: inHigh,
      highPass: mixOpenLow,
      lowPass: inLowPass,
      dry: 1,
      echo: 0,
    ),
  );
}
