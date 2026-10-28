import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/sleep_timer.dart';

void main() {
  late double volume;
  late int stops;
  late List<double> writes;
  late List<Object> errors;
  late SleepTimer timer;
  setUp(() {
    volume = 0.65;
    stops = 0;
    writes = [];
    errors = [];
    timer = SleepTimer(
      readVolume: () => volume,
      writeVolume: (value) async {
        volume = value;
        writes.add(value);
      },
      onExpired: () async {
        stops++;
      },
      onError: (error, _) => errors.add(error),
    );
  });
  tearDown(() => timer.cancel());

  test(
    'short timers fade to silence on schedule and restore chosen volume',
    () async {
      await timer.start(const Duration(milliseconds: 220));
      await Future<void>.delayed(const Duration(milliseconds: 360));
      expect(stops, 1);
      expect(writes, contains(0.0));
      expect(writes.any((v) => v > 0 && v < 0.6), isTrue);
      expect(volume, 0.65);
      expect(errors, isEmpty);
    },
  );

  test('cancel during fade restores volume and never stops playback', () async {
    await timer.start(const Duration(milliseconds: 300));
    await Future<void>.delayed(const Duration(milliseconds: 130));
    expect(volume, lessThan(0.65));
    await timer.cancel();
    expect(volume, 0.65);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(stops, 0);
  });

  test(
    'replacing a fading timer cannot let the old timer stop the new one',
    () async {
      await timer.start(const Duration(milliseconds: 240));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await timer.start(const Duration(seconds: 10));
      expect(volume, 0.65);
      await Future<void>.delayed(const Duration(milliseconds: 260));
      expect(stops, 0);
      expect(volume, 0.65);
    },
  );

  test(
    'overlapping commands wait for an in-flight write before restoring',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var first = true;
      timer = SleepTimer(
        readVolume: () => volume,
        writeVolume: (value) async {
          if (first) {
            first = false;
            started.complete();
            await release.future;
          }
          volume = value;
        },
        onExpired: () async {
          stops++;
        },
        onError: (error, _) => errors.add(error),
      );
      await timer.start(const Duration(milliseconds: 100));
      await started.future;
      final cancel = timer.cancel();
      final replace = timer.start(const Duration(seconds: 10));
      release.complete();
      await Future.wait([cancel, replace]);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(volume, 0.65);
      expect(stops, 0);
    },
  );

  test('a failed fade restores volume and reports its error', () async {
    var count = 0;
    timer = SleepTimer(
      readVolume: () => volume,
      writeVolume: (value) async {
        if (++count == 2) throw StateError('platform volume failure');
        volume = value;
      },
      onExpired: () async {
        stops++;
      },
      onError: (error, _) => errors.add(error),
    );
    await timer.start(const Duration(milliseconds: 200));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(errors, hasLength(1));
    expect(volume, 0.65);
  });
}
