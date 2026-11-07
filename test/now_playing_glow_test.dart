import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/now_playing_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/artwork_glow.dart';

import 'support/app_harness.dart';

class _Handler extends MusifyAudioHandler {
  @override
  Stream<List<Map>> get queueAsMapStream => Stream.value([
    {'ytid': 'a', 'title': 'Song', 'artist': 'Artist'},
  ]);
}

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('zenify_player_glow');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box, bytes: Uint8List(0));
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  testWidgets('the player glow waits for the page to arrive', (tester) async {
    audioHandler = _Handler();
    showPlayerVisualizer.value = false;
    audioHandler.mediaItem.add(
      const MediaItem(
        id: 'a',
        title: 'Song',
        duration: Duration(minutes: 3),
        extras: {'ytid': 'a'},
      ),
    );
    await tester.pumpWidget(localizedApp(const Scaffold()));
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(buildNowPlayingRoute());

    bool waiting() => tester
        .widget<PageGlow>(find.byType(PageGlow, skipOffstage: false))
        .waiting;

    // First frames: the route's own animation still claims to be complete.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(waiting(), isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    expect(waiting(), isTrue);

    // Arrived.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(waiting(), isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}
