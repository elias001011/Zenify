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

import 'package:just_audio/just_audio.dart';

/// How much of a song the Android player (ExoPlayer) loads ahead, by the
/// "Load songs far ahead" setting (`bufferWholeSong`).
///
/// Off, the player keeps the Musify way: about a minute ahead, so a skipped
/// song costs little data.
///
/// On, ExoPlayer loads until the maximum is buffered, then waits until the
/// buffer falls under the minimum. Both at ten minutes means a whole song is
/// loaded and kept, so a slow connection that has delivered the data cannot cut
/// the song off later, at the price of the data of songs that are skipped. The
/// desktop player (libmpv) already reads a whole song ahead; see
/// `JustAudioMediaKit.rebufferWait` for its stall wait.
AudioLoadConfiguration playbackLoadConfigurationFor({
  required bool wholeSong,
}) => wholeSong ? wholeSongLoadConfiguration : musifyLoadConfiguration;

const musifyLoadConfiguration = AudioLoadConfiguration(
  androidLoadControl: AndroidLoadControl(
    maxBufferDuration: Duration(seconds: 60),
    bufferForPlaybackDuration: Duration(milliseconds: 500),
    bufferForPlaybackAfterRebufferDuration: Duration(seconds: 3),
  ),
);

const wholeSongLoadConfiguration = AudioLoadConfiguration(
  androidLoadControl: AndroidLoadControl(
    minBufferDuration: Duration(minutes: 10),
    maxBufferDuration: Duration(minutes: 10),
    // A song still starts as soon as half a second is loaded.
    bufferForPlaybackDuration: Duration(milliseconds: 500),
    // After a stall, wait for a margin that outlasts the next hiccup.
    bufferForPlaybackAfterRebufferDuration: Duration(seconds: 8),
    // Memory limit. ExoPlayer's default for audio (12.5 MiB) would cut ten
    // minutes of a 256 kbps stream (18 MiB). Time does not override it, and
    // no back buffer is kept (it would count against this limit), so a large
    // local file (FLAC, WAV) can neither exhaust memory nor starve the player.
    targetBufferBytes: 32 * 1024 * 1024,
  ),
);
