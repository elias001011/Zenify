import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:just_audio/just_audio.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/settings_manager.dart';

void main() {
  late Directory dir;
  late DateTime now;
  late ListeningStatsService stats;
  final song = {'ytid': 'track', 'title': 'Track', 'duration': 300};
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zenify_stats_resume');
    Hive.init(dir.path);
    await Hive.openBox('settings');
    await Hive.openBox('user');
    wrappedEnabled.value = true;
    now = DateTime(2026, 11, 5, 12);
    stats = ListeningStatsService(now: () => now);
  });
  tearDown(() async {
    await stats.flush();
    await Hive.close();
    await dir.delete(recursive: true);
  });
  int seconds() => stats.monthStats('2026-11')?['totalSeconds'] as int? ?? 0;
  void advance(int seconds) => now = now.add(Duration(seconds: seconds));
  void state(bool playing, {Map? currentSong}) =>
      stats.handlePlayerStateForListeningStats(
        PlayerState(playing, ProcessingState.ready),
        currentSong: currentSong,
      );

  test('resuming with no song to credit does not count the pause', () {
    stats.startListeningSession(song);
    advance(10);
    state(false);
    expect(seconds(), 10);

    // A song played outside the queue: the queue song is not what plays.
    advance(600);
    state(true);
    advance(10);
    state(false);

    expect(seconds(), 20);
  });

  test('resuming with no song to credit opens no session', () {
    // A radio station: the session was closed and nothing is credited.
    state(true);
    advance(10);
    state(false);

    expect(seconds(), 0);
  });
}
