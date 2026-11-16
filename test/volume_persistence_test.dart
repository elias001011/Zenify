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

  test('a mute is not kept, so the app does not open silent', () async {
    final first = MusifyAudioHandler();
    await first.setVolume(0.6);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await first.setVolume(0);
    await Future<void>.delayed(const Duration(milliseconds: 700));

    expect(MusifyAudioHandler().volume, 0.6);
  });
}
