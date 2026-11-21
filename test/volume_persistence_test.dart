import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:musify/services/audio_service.dart';

import 'support/app_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppSettings();
  setUp(() => Hive.box('settings').delete('volume'));

  test('the volume chosen is there the next time the app opens', () async {
    final first = MusifyAudioHandler();
    await first.setVolume(0.4);
    await Future<void>.delayed(const Duration(milliseconds: 700));

    final next = MusifyAudioHandler();
    expect(next.volume, 0.4);
    expect(next.audioPlayer.volume, 0.4);
  });

  test(
    'a pending volume save tolerates closed settings during restore',
    () async {
      final handler = MusifyAudioHandler();
      await handler.setVolume(0.4);
      await Hive.box('settings').close();
      try {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        expect(Hive.isBoxOpen('settings'), isFalse);
        expect(handler.volume, 0.4);
      } finally {
        await Hive.openBox('settings');
      }
    },
  );

  test('a mute is not kept, so the app does not open silent', () async {
    final first = MusifyAudioHandler();
    await first.setVolume(0.6);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await first.setVolume(0);
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(MusifyAudioHandler().volume, 0.6);
  });

  test('muting during the debounce keeps the last audible choice', () async {
    await Hive.box('settings').put('volume', 0.8);
    final handler = MusifyAudioHandler();
    await handler.setVolume(0.4);
    await handler.setVolume(0);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    expect(MusifyAudioHandler().volume, 0.4);
  });

  test(
    'flushing before window close saves the audible choice immediately',
    () async {
      final handler = MusifyAudioHandler();
      await handler.setVolume(0.4);
      await handler.setVolume(0);
      await handler.flushVolume();
      expect(Hive.box('settings').get('volume'), 0.4);
    },
  );

  test('the sleep fade cannot become the saved volume', () async {
    final handler = MusifyAudioHandler();
    await handler.setVolume(0.6);
    await handler.setSleepTimer(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 700));
    try {
      expect(Hive.box('settings').get('volume'), 0.6);
    } finally {
      await handler.cancelSleepTimer();
    }
  });
}
