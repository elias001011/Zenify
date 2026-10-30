import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/audio_levels.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  test('phones never check permission or start an audio reader', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final calls = <String>[];
    for (final name in ['zenify/audio_levels', 'zenify/audio_levels/frames']) {
      final channel = MethodChannel(name);
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call.method);
        return true;
      });
      addTearDown(
        () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
    }
    expect(await AudioLevels.available, isFalse);
    expect(await AudioLevels.listen().toList(), isEmpty);
    expect(calls, isEmpty);
  });
  test('Android has no recording permission or native audio capture', () {
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      isNot(contains('android.permission.RECORD_AUDIO')),
    );
    final activity = File(
      'android/app/src/main/kotlin/io/github/elias001011/zenify/MainActivity.kt',
    ).readAsStringSync();
    expect(activity, isNot(contains('Visualizer')));
    expect(activity, isNot(contains('requestPermissions')));
    expect(activity, contains('keepScreenAwake'));
  });
}
