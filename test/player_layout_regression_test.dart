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
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        final size = paragraph.size;
        final boxes = paragraph
            .getBoxesForSelection(
              const TextSelection(baseOffset: 0, extentOffset: text.length),
            )
            .map((box) => box.toRect())
            .toList();
        final inactiveColor = paragraph.text.style!.color;
        final weight = paragraph.text.style!.fontWeight;
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
          expect(paragraph.size, size);
          expect(paragraph.text.style!.fontWeight, weight);
          expect(
            paragraph
                .getBoxesForSelection(
                  const TextSelection(baseOffset: 0, extentOffset: text.length),
                )
                .map((box) => box.toRect())
                .toList(),
            boxes,
          );
        }
        expect(paragraph.text.style!.color, isNot(inactiveColor));
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
