import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/screen_awake.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('zenify/display');
  final requests = <bool>[];
  setUp(() {
    requests.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      requests.add(call.arguments as bool);
      return null;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
  test(
    'Android releases the window flag only after the last lyrics panel closes',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final release = ScreenAwake.acquire(Stream.value(true));
      final releaseOther = ScreenAwake.acquire(Stream.value(true));
      await Future<void>.delayed(Duration.zero);
      expect(requests, [true]);
      release();
      await Future<void>.delayed(Duration.zero);
      expect(requests, [true]);
      releaseOther();
      releaseOther();
      await Future<void>.delayed(Duration.zero);
      expect(requests, [true, false]);
    },
  );
  test('the screen may sleep while the music is paused', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final playing = StreamController<bool>();
    final release = ScreenAwake.acquire(playing.stream);
    playing.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(requests, isEmpty);
    playing
      ..add(true)
      ..add(true);
    await Future<void>.delayed(Duration.zero);
    expect(requests, [true]);
    playing.add(false);
    await Future<void>.delayed(Duration.zero);
    expect(requests, [true, false]);
    playing.add(true);
    await Future<void>.delayed(Duration.zero);
    release();
    await Future<void>.delayed(Duration.zero);
    expect(requests, [true, false, true, false]);
    expect(playing.hasListener, isFalse);
  });
  test('desktop never changes the screen power policy', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    ScreenAwake.acquire(Stream.value(true))();
    await Future<void>.delayed(Duration.zero);
    expect(requests, isEmpty);
  });
}
