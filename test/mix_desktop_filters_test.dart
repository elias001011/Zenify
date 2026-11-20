import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:musify/services/audio_levels.dart';
import 'package:musify/services/mix_playlists.dart';
import 'package:musify/services/settings_manager.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings(inMemory: true);

  bool has(String label) =>
      JustAudioMediaKit.audioFilters.any((f) => f.startsWith('@$label:'));

  test('the desktop chain holds only the filters in use', () {
    equalizerEnabled.value = false;
    showPlayerVisualizer.value = false;
    waveReading.value = WaveReading.precise;
    mixTransitions.value = true;
    mixPlaylists.value = {};
    AudioLevels.configureDesktop();
    expect(has('zviz'), isFalse);
    showPlayerVisualizer.value = true;
    expect(has('zviz'), isTrue);
    for (final label in ['zmixl', 'zmixe', 'zuser0', 'zuser4']) {
      expect(has(label), isFalse, reason: label);
    }

    equalizerEnabled.value = true;
    expect(has('zuser0'), isTrue);
    expect(has('zmixl'), isFalse);
    // The readings stay last, after what they measure.
    expect(JustAudioMediaKit.audioFilters.last, startsWith('@zviz:'));

    mixPlaylists.value = {'playlist'};
    expect(has('zmixl'), isFalse);
    expect(has('zmixe'), isFalse);

    mixTransitions.value = false;
    equalizerEnabled.value = false;
    expect(JustAudioMediaKit.audioFilters.length, 1);
  });
}
