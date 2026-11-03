import 'dart:async';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/models/position_data.dart';
import 'package:musify/services/lyrics/lyrics_models.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/app_logo.dart';
import 'package:musify/widgets/floating_island.dart';
import 'package:musify/widgets/no_artwork_cube.dart';
import 'package:musify/widgets/now_playing/lyric_line_fill.dart';
import 'package:musify/widgets/now_playing/synced_lyrics_view.dart';
import 'package:musify/widgets/playlist_page/playlist_sliver_app_bar.dart';

import 'support/wave_test_handler.dart';

class _LyricsHandler extends WaveTestHandler {
  final positions = StreamController<PositionData>.broadcast();
  @override
  Stream<PositionData> get positionDataStream => positions.stream;
  @override
  PositionData get currentPositionData =>
      PositionData(Duration.zero, Duration.zero, const Duration(minutes: 3));
}

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('zenify_player_layout');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box);
    }
    floatingEffect.value = FloatingEffect.solid;
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  testWidgets('compact lyrics rise and stretch smoothly without overshoot', (
    tester,
  ) async {
    final handler = _LyricsHandler();
    audioHandler = handler;
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 350,
            height: 400,
            child: SyncedLyricsView(
              lyrics: Lyrics(
                source: 'test',
                synced: [
                  LyricLine(Duration.zero, 'First verse'),
                  LyricLine(Duration(seconds: 10), 'Second verse'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    handler.positions.add(
      PositionData(
        const Duration(seconds: 12),
        Duration.zero,
        const Duration(seconds: 20),
      ),
    );
    var previousScale = 0.98;
    var previousOffset = 3.0;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final transforms = tester.widgetList<Transform>(
        find.ancestor(
          of: find.text('Second verse'),
          matching: find.byType(Transform),
        ),
      );
      final scale = transforms
          .map((t) => t.transform.entry(1, 1))
          .reduce((a, b) => a < b ? a : b);
      final offset = transforms
          .map((t) => t.transform.getTranslation().y)
          .reduce((a, b) => a > b ? a : b);
      expect(scale, inInclusiveRange(previousScale - 0.00001, 1.00001));
      expect(offset, inInclusiveRange(-0.00001, previousOffset + 0.00001));
      previousScale = scale;
      previousOffset = offset;
    }
    expect(previousScale, closeTo(1, 0.00001));
    expect(previousOffset, closeTo(0, 0.00001));
    await tester.pumpWidget(const SizedBox());
    await handler.positions.close();
  });

  testWidgets(
    'verse handoff keeps its painter and scrolls through intermediate positions',
    (tester) async {
      final handler = _LyricsHandler();
      audioHandler = handler;
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 320,
              height: 240,
              child: SyncedLyricsView(
                lyrics: Lyrics(
                  source: 'test',
                  synced: [
                    LyricLine(Duration.zero, 'First verse'),
                    LyricLine(Duration(seconds: 10), 'Second verse'),
                    LyricLine(Duration(seconds: 20), 'Third verse'),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final second = find.ancestor(
        of: find.text('Second verse'),
        matching: find.byType(LyricLineFill),
      );
      final state = tester.state(second);
      final viewport = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      final start = viewport.pixels;
      handler.positions.add(
        PositionData(
          const Duration(seconds: 11),
          Duration.zero,
          const Duration(seconds: 30),
        ),
      );
      await tester.pump();
      expect(tester.state(second), same(state));
      await tester.pump();
      final samples = <double>[];
      for (var i = 0; i < 18; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        samples.add(viewport.pixels);
      }
      final end = samples.last;
      expect(end, greaterThan(start));
      expect(samples.where((p) => p > start && p < end).length, greaterThan(3));
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i], greaterThanOrEqualTo(samples[i - 1]));
      }
      expect(tester.state(second), same(state));
      await tester.pumpWidget(const SizedBox());
      await handler.positions.close();
    },
  );

  testWidgets('desktop lyric fill follows seek and settles while paused', (
    tester,
  ) async {
    final handler = _LyricsHandler();
    audioHandler = handler;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SyncedLyricsView(
            lyrics: Lyrics(
              source: 'test',
              synced: [
                LyricLine(Duration.zero, 'First verse'),
                LyricLine(Duration(seconds: 10), 'Second verse'),
                LyricLine(Duration(seconds: 20), 'Last verse'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is LyricLineFill && widget.emphasis == 1,
        ),
        matching: find.text('First verse'),
      ),
      findsOneWidget,
    );
    handler.positions.add(
      PositionData(
        const Duration(seconds: 14),
        Duration.zero,
        const Duration(seconds: 30),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is LyricLineFill && widget.emphasis == 1,
        ),
        matching: find.text('Second verse'),
      ),
      findsOneWidget,
    );
    expect(tester.binding.hasScheduledFrame, isFalse);
    handler.positions.add(
      PositionData(
        const Duration(seconds: 3),
        Duration.zero,
        const Duration(seconds: 30),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is LyricLineFill && widget.emphasis == 1,
        ),
        matching: find.text('First verse'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await handler.positions.close();
  });

  testWidgets(
    'synced lyrics keep word positions and line height through highlight',
    (tester) async {
      final handler = _LyricsHandler();
      audioHandler = handler;
      const text = 'The final word should always stay on the same line';
      for (final width in [260.0, 350.0, 600.0]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: width,
                height: 400,
                child: const SyncedLyricsView(
                  lyrics: Lyrics(
                    source: 'test',
                    synced: [
                      LyricLine(Duration(seconds: 1), text),
                      LyricLine(Duration(seconds: 5), 'Another line'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final finder = find.text(text);
        RenderParagraph paragraph() =>
            tester.renderObject<RenderParagraph>(finder);
        final size = paragraph().size;
        final boxes = paragraph()
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: text.length),
            )
            .map((box) => box.toRect())
            .toList();
        final inactiveColor = paragraph().text.style!.color;
        final weight = paragraph().text.style!.fontWeight;
        handler.positions.add(
          PositionData(
            const Duration(seconds: 2),
            Duration.zero,
            const Duration(minutes: 3),
          ),
        );
        await tester.pump();
        // Check every phase of the highlight, including intermediate frames.
        for (var frame = 0; frame < 8; frame++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(paragraph().size, size);
          expect(paragraph().text.style!.fontWeight, weight);
          expect(
            paragraph()
                .getBoxesForSelection(
                  const TextSelection(baseOffset: 0, extentOffset: text.length),
                )
                .map((box) => box.toRect())
                .toList(),
            boxes,
          );
        }
        expect(paragraph().text.style!.color, isNot(inactiveColor));
        await tester.pumpWidget(const SizedBox());
      }
      await handler.positions.close();
    },
  );

  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1280, 800),
  ]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets(
        'island waits for the whole title to leave ($size, scale $scale)',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final titleKey = GlobalKey();
          final controller = ScrollController();
          const title =
              'A long playlist title that can wrap onto a second line';
          final islandTitle = find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data == title &&
                widget.style?.fontFamily == 'paytoneOne',
          );
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  viewPadding: const EdgeInsets.only(top: 24),
                  textScaler: TextScaler.linear(scale),
                ),
                child: IslandScaffold(
                  title: title,
                  headerTitleKey: titleKey,
                  globalSearch: false,
                  body: CustomScrollView(
                    controller: controller,
                    slivers: [
                      PlaylistSliverAppBar(
                        title: title,
                        titleKey: titleKey,
                        playlist: const {},
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 2000)),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(islandTitle, findsNothing);
          final bottom = tester.getBottomLeft(find.byKey(titleKey)).dy;
          // Even if only the bottom ten pixels of the title are visible,
          // the island must remain compact.
          controller.jumpTo(bottom - 24 - 10);
          await tester.pumpAndSettle();
          expect(islandTitle, findsNothing);
          controller.jumpTo(bottom - 24 + 1);
          await tester.pumpAndSettle();
          expect(islandTitle, findsOneWidget);
          controller.jumpTo(1000);
          await tester.pumpAndSettle();
          expect(islandTitle, findsOneWidget);
          controller.jumpTo(bottom - 24 - 10);
          await tester.pumpAndSettle();
          expect(islandTitle, findsNothing);
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        },
      );
    }
  }

  testWidgets('missing song artwork uses the current app logo', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NullArtworkWidget()));
    expect(find.byType(AppLogo), findsOneWidget);
  });
}
