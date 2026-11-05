import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/listening_stats_utils.dart';

import 'support/app_harness.dart';

/// Regression test for gokadzev/Musify#953: after the last song in the queue
/// completes, just_audio keeps `playing == true`, and the resulting
/// `PlayerState(playing: true, completed)` event must not start a new
/// listening session that keeps counting idle wall-clock time.
void main() {
  final song = {'ytid': 'aaa', 'title': 'A', 'artist': 'x', 'duration': 5};

  useAppSettings(boxes: ['settings', 'user']);
  setUpAll(() {
    wrappedEnabled.value = true;
  });

  int monthTotal(ListeningStatsService service) {
    final month = service.monthStats(listeningStatsMonthKey(DateTime.now()));
    return monthTotalSeconds(Map<String, dynamic>.from(month ?? const {}));
  }

  Future<void> tick() => Future<void>.delayed(const Duration(seconds: 1));

  test('idle time after the queue ends is not counted', () async {
    final service = ListeningStatsService()
      ..startListeningSession(song, duration: const Duration(seconds: 5))
      ..handlePlayerStateForListeningStats(
        PlayerState(true, ProcessingState.ready),
        currentSong: song,
      );
    await tick();

    // processingStateStream -> completed (audio_service finishes the session).
    service.finishListeningSession(countCurrentTick: true, wasPlaying: true);
    final listened = monthTotal(service);
    expect(listened, greaterThanOrEqualTo(1));

    // playerStateStream -> (playing: true, completed).
    service.handlePlayerStateForListeningStats(
      PlayerState(true, ProcessingState.completed),
      currentSong: song,
    );
    await tick();
    await tick();

    // App backgrounded / paused while the player still reports playing.
    service
      ..recordListeningSessionProgress(wasPlaying: true)
      ..handlePlayerStateForListeningStats(
        PlayerState(false, ProcessingState.completed),
        currentSong: song,
      );

    expect(monthTotal(service), listened);
  });

  test(
    'a completed event before the session is finished stops counting',
    () async {
      final service = ListeningStatsService();
      final before = monthTotal(service);

      service.startListeningSession(song, duration: const Duration(seconds: 5));
      await tick();

      // Completed arrives while the session is still open: counts the final
      // tick, then the session must stay frozen until it is finished.
      service.handlePlayerStateForListeningStats(
        PlayerState(true, ProcessingState.completed),
        currentSong: song,
      );
      final afterCompleted = monthTotal(service);
      expect(afterCompleted, greaterThanOrEqualTo(before + 1));

      await tick();
      await tick();
      service.finishListeningSession(countCurrentTick: true);

      expect(monthTotal(service), afterCompleted);
    },
  );

  test('replaying after completion starts counting again', () async {
    final service = ListeningStatsService();
    final before = monthTotal(service);

    service.handlePlayerStateForListeningStats(
      PlayerState(true, ProcessingState.completed),
      currentSong: song,
    );
    await tick();
    expect(monthTotal(service), before);

    // playAgain(): new session, then the player reports ready + playing.
    service
      ..startListeningSession(song, duration: const Duration(seconds: 5))
      ..handlePlayerStateForListeningStats(
        PlayerState(true, ProcessingState.ready),
        currentSong: song,
      );
    await tick();
    service.recordListeningSessionProgress();

    expect(monthTotal(service), greaterThanOrEqualTo(before + 1));
  });
}
