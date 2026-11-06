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

/// One band of an equalizer: its center frequency in Hz and its gain in dB.
typedef EqualizerBand = ({double centerFrequency, double gain});

/// What the equalizer page needs to know of an equalizer, whichever engine
/// runs it: the gain range in dB and the bands, lowest frequency first.
typedef EqualizerParameters = ({
  double minDecibels,
  double maxDecibels,
  List<EqualizerBand> bands,
});
