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

/// Owns the countdown and its final fade. Commands invalidate a fade before
/// awaiting a platform volume write, so an old timer cannot stop a new one.
class SleepTimer {
  SleepTimer({
    required this.readVolume,
    required this.writeVolume,
    required this.onExpired,
    required this.onError,
  });

  final double Function() readVolume;
  final Future<void> Function(double) writeVolume;
  final Future<void> Function() onExpired;
  final void Function(Object, StackTrace) onError;
  Timer? _timer;
  int _generation = 0;
  double? _originalVolume;
  Future<void> _pendingWrite = Future.value();
  static const fadeDuration = Duration(seconds: 6);

  Future<int> cancel() async {
    final generation = ++_generation;
    _timer?.cancel();
    _timer = null;
    final original = _originalVolume;
    _originalVolume = null;
    // Serialize restoration after the last platform write, even when another
    // command already took ownership of the original volume.
    final previousWrite = _pendingWrite;
    _pendingWrite = () async {
      try {
        await previousWrite;
      } catch (_) {
        // A failed fade write still needs a restore attempt.
      }
      if (original != null) await writeVolume(original);
    }();
    try {
      await _pendingWrite;
    } catch (error, stack) {
      if (generation == _generation) onError(error, stack);
    }
    return generation;
  }

  Future<void> start(Duration duration) async {
    final generation = await cancel();
    if (generation != _generation) return;
    final total = duration < Duration.zero ? Duration.zero : duration;
    final fade = total < fadeDuration ? total : fadeDuration;
    _timer = Timer(total - fade, () => unawaited(_fade(generation, fade)));
  }

  Future<void> _fade(int generation, Duration duration) async {
    if (generation != _generation) return;
    _timer = null;
    final original = readVolume();
    _originalVolume = original;
    final elapsed = Stopwatch()..start();
    try {
      while (generation == _generation) {
        final fraction = duration.inMicroseconds == 0
            ? 1.0
            : (elapsed.elapsedMicroseconds / duration.inMicroseconds).clamp(
                0.0,
                1.0,
              );
        _pendingWrite = writeVolume(original * (1 - fraction));
        await _pendingWrite;
        if (generation != _generation) return;
        if (fraction >= 1) break;
        final remaining = duration - elapsed.elapsed;
        if (remaining > Duration.zero) {
          await Future<void>.delayed(
            remaining < const Duration(milliseconds: 100)
                ? remaining
                : const Duration(milliseconds: 100),
          );
        }
      }
      if (generation == _generation) await onExpired();
    } catch (error, stack) {
      if (generation == _generation) onError(error, stack);
    } finally {
      elapsed.stop();
      if (generation == _generation) {
        _pendingWrite = Future<void>.sync(() => writeVolume(original));
        _originalVolume = null;
        try {
          await _pendingWrite;
        } catch (error, stack) {
          if (generation == _generation) onError(error, stack);
        }
      }
    }
  }
}
