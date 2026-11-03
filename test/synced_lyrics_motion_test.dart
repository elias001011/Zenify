import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/models/position_data.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/lyrics/lyrics_models.dart';
import 'package:musify/widgets/now_playing/lyric_line_fill.dart';
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
    dir = await Directory.systemTemp.createTemp('zenify_lyrics_motion');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box, bytes: Uint8List(0));
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  final lyrics = Lyrics(
    source: 'test',
    synced: [
      for (var i = 0; i < 40; i++) LyricLine(Duration(seconds: i * 10), 'V$i'),
    ],
  );

  Future<_Handler> pumpLyrics(WidgetTester tester) async {
    final handler = _Handler();
    audioHandler = handler;
    addTearDown(handler.positions.close);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SyncedLyricsView(lyrics: lyrics)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    return handler;
  }

  Finder row(int index) => find
      .ancestor(
        of: find.text('V$index'),
        matching: find.byType(GestureDetector),
      )
      .first;

  /// How far the row is lifted or dropped, in pixels (up is negative).
  double lean(WidgetTester tester, int index) => tester
      .widget<Transform>(
        find.descendant(of: row(index), matching: find.byType(Transform)).first,
      )
      .transform
      .getTranslation()
      .y;

  testWidgets('the sung line rises between its neighbours, evenly', (
    tester,
  ) async {
    await pumpLyrics(tester);

    // Line 16 is being sung: it keeps its place, the sung line above it gives
    // way by as much as the next one below, so the gaps stay equal.
    expect(lean(tester, 16), closeTo(0, 0.01));
    expect(lean(tester, 15), closeTo(-3, 0.01));
    expect(lean(tester, 17), closeTo(3, 0.01));
    expect(lean(tester, 12), closeTo(-3, 0.01));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('a line change rebuilds the rows that changed, not the song', (
    tester,
  ) async {
    final handler = await pumpLyrics(tester);

    var rebuilt = 0;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      if (element.widget is LyricLineFill) rebuilt++;
    };
    try {
      handler.positions.add(
        PositionData(
          const Duration(seconds: 175),
          Duration.zero,
          const Duration(minutes: 5),
        ),
      );
      await tester.idle();
      await tester.pump();
    } finally {
      debugOnRebuildDirtyWidget = null;
    }

    // The old row and the new one; the other 38 are left alone.
    expect(rebuilt, inInclusiveRange(1, 4));

    await tester.pump(const Duration(seconds: 2));
    expect(lean(tester, 17), closeTo(0, 0.01));
    expect(lean(tester, 16), closeTo(-3, 0.01));
    expect(lean(tester, 18), closeTo(3, 0.01));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
