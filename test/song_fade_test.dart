import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/song_fade.dart';

Duration _s(num seconds) => Duration(microseconds: (seconds * 1e6).round());

void main() {
  group('songFadeLength', () {
    test('is the chosen length for a song of three times that or more', () {
      expect(songFadeLength(_s(18), 6), _s(6));
      expect(songFadeLength(_s(240), 6), _s(6));
    });

    test('is a third of a shorter song', () {
      expect(songFadeLength(_s(15), 6), _s(5));
      expect(songFadeLength(_s(9), 6), _s(3));
      expect(songFadeLength(_s(2), 6), _s(2) ~/ 3);
    });

    test('is the chosen length while the duration is unknown', () {
      expect(songFadeLength(null, 6), _s(6));
    });
  });

  group('songFadeGain', () {
    double gain(
      num position, {
      num? duration = 240,
      int seconds = 6,
      bool fadeIn = true,
      bool fadeOut = true,
    }) => songFadeGain(
      position: _s(position),
      duration: duration == null ? null : _s(duration),
      seconds: seconds,
      fadeIn: fadeIn,
      fadeOut: fadeOut,
    );

    test('fades in over the first seconds', () {
      expect(gain(0), 0);
      expect(gain(3), closeTo(sin(pi / 4), 1e-9));
      expect(gain(6), 1);
      expect(gain(6.001), 1);
      expect(gain(60), 1);
    });

    test('fades out over the last seconds', () {
      expect(gain(234), 1);
      expect(gain(237), closeTo(cos(pi / 4), 1e-9));
      expect(gain(240), closeTo(0, 1e-9));
    });

    test('stays silent at the end if the position goes past the song', () {
      expect(gain(241), closeTo(0, 1e-9));
    });

    test('rises and falls along the same equal-power curve', () {
      for (var t = 0.0; t <= 6; t += 0.25) {
        final rising = gain(t, fadeOut: false);
        final falling = gain(234 + t, fadeIn: false);
        expect(rising * rising + falling * falling, closeTo(1, 1e-9));
      }
    });

    test('takes about 120 steps over six seconds at one every 50 ms', () {
      final values = {
        for (var ms = 0; ms <= 6000; ms += 50)
          gain(234 + ms / 1000, fadeIn: false),
      };
      expect(values.length, 121);
    });

    test('is off at 0 seconds', () {
      for (final position in [0, 3, 120, 237, 240]) {
        expect(gain(position, seconds: 0), 1, reason: '$position s');
      }
    });

    test('has no fade-in unless the song began by an automatic advance', () {
      expect(gain(0, fadeIn: false), 1);
      expect(gain(1, fadeIn: false), 1);
      // The fade-out is still there.
      expect(gain(240, fadeIn: false), closeTo(0, 1e-9));
    });

    test('has no fade-out unless another song follows', () {
      expect(gain(237, fadeOut: false), 1);
      expect(gain(240, fadeOut: false), 1);
      expect(gain(0, fadeOut: false), 0);
    });

    test('shortens both fades to a third of a short song', () {
      // 12 s with 6 s: 4 s at each end, and a steady middle.
      expect(gain(0, duration: 12), 0);
      expect(gain(2, duration: 12), closeTo(sin(pi / 4), 1e-9));
      expect(gain(4, duration: 12), 1);
      expect(gain(6, duration: 12), 1);
      expect(gain(8, duration: 12), 1);
      expect(gain(10, duration: 12), closeTo(cos(pi / 4), 1e-9));
      expect(gain(12, duration: 12), closeTo(0, 1e-9));
    });

    test('never lets the two fades overlap', () {
      for (final duration in [3, 4.5, 9, 17, 18, 19]) {
        final length = songFadeLength(_s(duration), 6);
        final middle = _s(duration) ~/ 2;
        expect(
          songFadeGain(
            position: middle,
            duration: _s(duration),
            seconds: 6,
            fadeIn: true,
            fadeOut: true,
          ),
          1,
          reason: 'middle of a $duration s song (fade ${length.inSeconds} s)',
        );
      }
    });

    test('fades in but cannot fade out a song of unknown duration', () {
      expect(gain(3, duration: null), closeTo(sin(pi / 4), 1e-9));
      expect(gain(300, duration: null), 1);
    });

    test('is full for an empty song', () {
      expect(gain(0, duration: 0), 1);
      expect(gain(1, duration: 0), 1);
    });

    test('seeking out of a zone gives back the full volume', () {
      expect(gain(237), lessThan(0.8));
      expect(gain(100), 1);
      expect(gain(3), lessThan(0.8));
      expect(gain(100), 1);
    });
  });

  group('SongFade', () {
    late Duration position;
    late bool playing;
    late bool fadeOut;
    late int seconds;
    late List<double> writes;
    late SongFade fade;

    setUp(() {
      position = Duration.zero;
      playing = true;
      fadeOut = true;
      seconds = 6;
      writes = [];
      fade = SongFade(
        read: () => (
          position: position,
          duration: _s(60),
          seconds: seconds,
          fadeOut: fadeOut,
          playing: playing,
        ),
        write: () async => writes.add(fade.gain),
      );
    });

    /// Lets [time] go by in 10 ms steps, the song's position with it while it
    /// plays.
    Future<void> elapse(WidgetTester tester, Duration time) async {
      const step = Duration(milliseconds: 10);
      for (var passed = Duration.zero; passed < time; passed += step) {
        if (playing) position += step;
        await tester.pump(step);
      }
    }

    testWidgets('writes about every 50 ms through a fade-out, and only then', (
      tester,
    ) async {
      try {
        position = _s(30);
        await fade.update();
        await elapse(tester, const Duration(seconds: 10));
        // Out of the zone nothing runs: the position is 40 s, no write.
        expect(writes, isEmpty);

        // The coarse position updates find the song inside the zone.
        position = _s(54.1);
        await fade.update();
        expect(writes, hasLength(1));
        writes.clear();

        await elapse(tester, const Duration(milliseconds: 5800));
        // 5.8 s at one write every 50 ms.
        expect(writes.length, inInclusiveRange(115, 116));
        for (var i = 1; i < writes.length; i++) {
          expect(writes[i], lessThan(writes[i - 1]));
        }
        expect(writes.last, lessThan(0.05));

        playing = false;
        await fade.update();
        writes.clear();
        await elapse(tester, const Duration(seconds: 2));
        expect(writes, isEmpty);
      } finally {
        fade.cancel();
      }
    });

    testWidgets('pausing mid-fade keeps the gain and resuming continues', (
      tester,
    ) async {
      try {
        position = _s(55.5);
        await fade.update();
        await elapse(tester, const Duration(milliseconds: 500));
        final paused = fade.gain;
        expect(
          paused,
          closeTo(
            songFadeGain(
              position: _s(56),
              duration: _s(60),
              seconds: 6,
              fadeIn: false,
              fadeOut: true,
            ),
            0.01,
          ),
        );

        playing = false;
        await fade.update();
        writes.clear();
        await elapse(tester, const Duration(seconds: 3));
        expect(writes, isEmpty);
        expect(fade.gain, paused);

        playing = true;
        await fade.update();
        await elapse(tester, const Duration(milliseconds: 500));
        expect(writes, isNotEmpty);
        expect(writes.first, lessThan(paused));
        expect(writes.first, greaterThan(paused - 0.05));
      } finally {
        fade.cancel();
      }
    });

    testWidgets('seeking out of the zone restores the volume at once', (
      tester,
    ) async {
      try {
        position = _s(57);
        await fade.update();
        expect(fade.gain, lessThan(0.8));

        position = _s(20);
        await fade.update();
        expect(fade.gain, 1);
        expect(writes.last, 1);

        writes.clear();
        await elapse(tester, const Duration(seconds: 1));
        expect(writes, isEmpty);
      } finally {
        fade.cancel();
      }
    });

    testWidgets('a fade-in starts silent, rises, and is spent once', (
      tester,
    ) async {
      try {
        fade.fadeIn = true;
        await fade.update();
        expect(fade.gain, 0);
        expect(writes, [0]);

        await elapse(tester, const Duration(seconds: 7));
        expect(writes.length, inInclusiveRange(120, 124));
        for (var i = 1; i < writes.length; i++) {
          expect(writes[i], greaterThanOrEqualTo(writes[i - 1]));
        }
        expect(fade.gain, 1);
        expect(fade.fadeIn, isFalse);

        // Seeking back to the start does not fade in again.
        position = _s(1);
        await fade.update();
        expect(fade.gain, 1);
      } finally {
        fade.cancel();
      }
    });

    testWidgets('turning the fade off mid-fade gives back the volume', (
      tester,
    ) async {
      try {
        position = _s(57);
        await fade.update();
        expect(fade.gain, lessThan(0.8));

        seconds = 0;
        await elapse(tester, const Duration(milliseconds: 100));
        expect(fade.gain, 1);
      } finally {
        fade.cancel();
      }
    });

    testWidgets('a song that stops being followed by another stops fading', (
      tester,
    ) async {
      try {
        position = _s(57);
        await fade.update();
        expect(fade.gain, lessThan(0.8));

        // Repeat one, say, was chosen.
        fadeOut = false;
        await elapse(tester, const Duration(milliseconds: 100));
        expect(fade.gain, 1);
      } finally {
        fade.cancel();
      }
    });
  });
}
