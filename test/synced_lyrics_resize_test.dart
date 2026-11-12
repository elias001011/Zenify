import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/models/position_data.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/lyrics/lyrics_models.dart';
import 'package:musify/widgets/now_playing/synced_lyrics_view.dart';

class _Handler extends MusifyAudioHandler {
  final positions = StreamController<PositionData>.broadcast();
  @override
  PositionData get currentPositionData => PositionData(
    const Duration(seconds: 165),
    Duration.zero,
    const Duration(minutes: 5),
  );
  @override
  Stream<PositionData> get positionDataStream => positions.stream;
}

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('zenify_lyrics_resize');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box, bytes: Uint8List(0));
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  testWidgets(
    'maximizing and restoring keeps the current verse in place without a new position event',
    (tester) async {
      final handler = _Handler();
      audioHandler = handler;
      addTearDown(handler.positions.close);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1000, 650);
      addTearDown(tester.view.reset);
      final lyrics = Lyrics(
        source: 'test',
        synced: [
          for (var i = 0; i < 30; i++)
            LyricLine(
              Duration(seconds: i * 10),
              'Verse $i has enough words to wrap across the narrower lyrics panel',
            ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: SyncedLyricsView(lyrics: lyrics),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final state = tester.state(find.byType(SyncedLyricsView));
      void expectCurrentVerseAnchored() {
        final viewport = tester.getRect(find.byType(SingleChildScrollView));
        final verse = tester.getRect(
          find
              .ancestor(
                of: find.text(lyrics.synced![16].text),
                matching: find.byWidgetPredicate((w) => w is GestureDetector),
              )
              .first,
        );
        expect(
          verse.top,
          closeTo(viewport.top + (viewport.height - verse.height) * 0.4, 1),
        );
        expect(tester.state(find.byType(SyncedLyricsView)), same(state));
      }

      expectCurrentVerseAnchored();
      for (final size in [const Size(1920, 1080), const Size(1000, 650)]) {
        tester.view.physicalSize = size;
        await tester.pump();
        await tester.pump();
        expectCurrentVerseAnchored();
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    },
  );
}
