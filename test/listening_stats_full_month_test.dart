import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:musify/services/listening_stats_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/listening_stats_utils.dart';

void main() {
  late Directory dir;
  late DateTime now;
  late ListeningStatsService stats;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('zenify_stats_full_month');
    Hive.init(dir.path);
    await Hive.openBox('settings');
    await Hive.openBox('user');
    wrappedEnabled.value = true;
    now = DateTime(2026, 11, 3, 12);
    stats = ListeningStatsService(now: () => now);
    // A month whose songs were all heard to the end once: the least of them
    // has far more seconds than a song that has just qualified.
    for (var i = 0; i < wrappedCurrentMonthSongsLimit; i++) {
      stats.recordListening(
        {'ytid': 'old$i', 'title': 'Old $i'},
        Duration(seconds: 200 + i),
        incrementPlayCount: true,
      );
    }
  });
  tearDown(() async {
    await stats.flush();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Map<String, dynamic> songs() =>
      stats.monthStats('2026-11')!['songs'] as Map<String, dynamic>;

  void listen(Map<String, dynamic> song, int seconds) {
    stats.startListeningSession(song);
    now = now.add(Duration(seconds: seconds));
    stats.finishListeningSession(countCurrentTick: true, wasPlaying: true);
  }

  test('a song new to a full month counts, with everything heard of it', () {
    expect(songs(), hasLength(wrappedCurrentMonthSongsLimit));

    listen({'ytid': 'new', 'title': 'New'}, 100);

    expect(songs(), hasLength(wrappedCurrentMonthSongsLimit));
    expect(songs()['new'], containsPair('playCount', 1));
    expect(songs()['new'], containsPair('seconds', 100));
  });

  test('the least heard song makes room, never the one just played', () {
    listen({'ytid': 'new', 'title': 'New'}, 100);
    listen({'ytid': 'other', 'title': 'Other'}, 90);

    expect(songs(), hasLength(wrappedCurrentMonthSongsLimit));
    // The first newcomer took the place of the least heard of the month, the
    // second one took the first's: it had the fewest seconds by then.
    expect(songs(), contains('other'));
    expect(songs(), isNot(contains('new')));
    expect(songs(), isNot(contains('old0')));
    expect(songs(), contains('old1'));
  });
}
