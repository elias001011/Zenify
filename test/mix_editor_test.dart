import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/mix_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/mix_analysis.dart';
import 'package:musify/services/mix_edits.dart';
import 'package:musify/services/mix_transition.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/widgets/mix_editor.dart';
import 'package:musify/widgets/mix_timeline.dart';

import 'support/app_harness.dart';

const _a = {
  'ytid': 'a',
  'title': 'Noite Clara',
  'artist': 'Artista A',
  'duration': 200,
};
const _b = {
  'ytid': 'b',
  'title': 'Vento Sul',
  'artist': 'Artista B',
  'duration': 200,
};

class _Analyzer extends MixAnalyzer {
  _Analyzer() : super(locate: (_) async => null);
  bool fail = false;
  int requests = 0;

  @override
  Future<MixInspection?> inspect(
    Map song, {
    required bool tail,
    required Duration? duration,
  }) async {
    requests++;
    if (fail) return null;
    return (
      edge: MixEdge(
        sound: tail ? 199000 : 400,
        bpm: 120,
        beat: 0.8,
        beatAt: tail ? 160000 : 500,
        level: 0.2,
        soft: 1500,
      ),
      offset: tail ? 160000 : 0,
      length: 40000,
      wave: List.generate(400, (i) => 0.1 + 0.15 * sin(i * 0.6).abs()),
    );
  }
}

class _Handler extends Fake implements MusifyAudioHandler {
  int refreshes = 0;
  late MixAnalyzer analyzer;
  @override
  MixAnalyzer get mixAnalyzer => analyzer;
  List<MixSkip> opening = const [];
  @override
  Future<List<MixSkip>> mixSkips(Map song) async =>
      song['ytid'] == 'b' ? opening : const [];
  @override
  void refreshMix() => refreshes++;
  @override
  Future<void> stopMixPreview({bool resume = true}) async {}
}

void main() {
  useAppSettings(inMemory: true);
  setUpAll(() async {
    if (Platform.environment['MIX_FONT_DIR'] case final String directory) {
      for (final name in ['Regular', 'Filled']) {
        final loader =
            FontLoader(
              'packages/fluentui_system_icons/FluentSystemIcons-$name',
            )..addFont(
              rootBundle.load(
                'packages/fluentui_system_icons/fonts/FluentSystemIcons-$name.ttf',
              ),
            );
        await loader.load();
      }
      for (final (family, file) in [
        ('Roboto', 'Roboto-Regular.ttf'),
        ('MaterialIcons', 'MaterialIcons-Regular.otf'),
      ]) {
        final loader = FontLoader(family)
          ..addFont(
            Future.value(
              ByteData.sublistView(
                await File('$directory/$file').readAsBytes(),
              ),
            ),
          );
        await loader.load();
      }
    }
  });
  late _Analyzer analyzer;
  late _Handler handler;

  setUp(() async {
    await Hive.box('settings').clear();
    userCustomPlaylists.value = [];
    userPlaylistFolders.value = [];
    analyzer = _Analyzer();
    audioHandler = handler = _Handler()..analyzer = analyzer;
  });

  Future<void> open(WidgetTester tester, {Map song = _a}) async {
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: RepaintBoundary(
                      key: const ValueKey('mix-editor-shot'),
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        child: MixEditor(
                          playlist: 'p',
                          song: song,
                          next: _b,
                          analyzer: analyzer,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> openTracks(WidgetTester tester, {bool inFolder = false}) async {
    final playlist = {
      'ytid': 'customId-mix-test',
      'title': 'Noites de verão',
      'source': 'user-created',
      'list': [
        _a,
        _b,
        {..._a, 'ytid': 'c', 'title': 'Horizonte'},
      ],
    };
    if (inFolder) {
      userPlaylistFolders.value = [
        {
          'id': 'folder',
          'name': 'Folder',
          'playlists': [playlist],
        },
      ];
    } else {
      userCustomPlaylists.value = [playlist];
    }
    await tester.pumpWidget(
      localizedApp(
        const MixPage(playlist: 'customId-mix-test', song: _a, next: _b),
      ),
    );
    await tester.pumpAndSettle();
    if (tester.view.physicalSize.width / tester.view.devicePixelRatio < 1050) {
      await tester.tap(find.byTooltip('Tracks'));
      await tester.pumpAndSettle();
    }
  }

  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    for (final inFolder in [false, true]) {
      testWidgets(
        'dragging Mix tracks saves default order at $size, folder=$inFolder',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await mixEdits.set(
            'customId-mix-test',
            'a',
            'b',
            const MixEdit(
              outStart: Duration(seconds: 184),
              inStart: Duration(seconds: 1),
              length: Duration(seconds: 16),
              style: MixStyle.blend,
            ),
          );
          await openTracks(tester, inFolder: inFolder);
          // Move the last track above the first using the visible handle.
          final handles = find.byType(ReorderableDragStartListener);
          expect(handles, findsNWidgets(3));
          final start = tester.getCenter(handles.last);
          final end = Offset(
            start.dx,
            tester.getTopLeft(find.byKey(const ValueKey('mix-track-a'))).dy + 2,
          );
          final gesture = await tester.startGesture(start);
          await tester.pump();
          for (var step = 1; step <= 12; step++) {
            await gesture.moveTo(Offset.lerp(start, end, step / 12)!);
            await tester.pump(const Duration(milliseconds: 32));
          }
          await tester.pump(const Duration(milliseconds: 400));
          await gesture.up();
          await tester.pumpAndSettle();
          final current = inFolder
              ? userPlaylistFolders.value.single['playlists'][0]
              : userCustomPlaylists.value.single;
          expect((current['list'] as List).map((s) => s['ytid']), [
            'c',
            'a',
            'b',
          ]);
          final stored = inFolder
              ? (Hive.box(
                  'user',
                ).get('playlistFolders') as List).single['playlists'][0]
              : (Hive.box('user').get('customPlaylists') as List).single;
          expect((stored['list'] as List).map((s) => s['ytid']), [
            'c',
            'a',
            'b',
          ]);
          expect(
            mixEdits.get('customId-mix-test', 'a', 'b')!.length,
            const Duration(seconds: 16),
          );
          final editor = tester.widget<MixEditor>(find.byType(MixEditor));
          expect(editor.song['ytid'], 'a');
          expect(editor.next['ytid'], 'b');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('reorder down uses final index and preserves latest metadata', (
    tester,
  ) async {
    await openTracks(tester);
    final stored = userCustomPlaylists.value.single;
    stored['title'] = 'Renamed playlist';
    stored['list'][0] = {..._a, 'title': 'Renamed track'};
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorderItem!(0, 2);
    await tester.pumpAndSettle();
    final saved = (Hive.box('user').get('customPlaylists') as List).single;
    expect((saved['list'] as List).map((s) => s['ytid']), ['b', 'c', 'a']);
    expect(saved['title'], 'Renamed playlist');
    expect(saved['list'][2]['title'], 'Renamed track');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a concurrent playlist change is not overwritten by Mix reorder',
    (tester) async {
      await openTracks(tester);
      final stored = userCustomPlaylists.value.single;
      stored['list'] = [stored['list'][2], _b, _a];
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(0, 2);
      await tester.pumpAndSettle();
      expect((stored['list'] as List).map((s) => s['ytid']), ['c', 'b', 'a']);
      final list = find.byType(ReorderableListView);
      expect(
        tester
            .getTopLeft(
              find.descendant(of: list, matching: find.text('Horizonte')),
            )
            .dy,
        lessThan(
          tester
              .getTopLeft(
                find.descendant(of: list, matching: find.text('Vento Sul')),
              )
              .dy,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(360, 800), const Size(1200, 900)]) {
    testWidgets('editor lays out waveforms and controls at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await open(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Edit transition'), findsOneWidget);
      expect(find.text('120 BPM'), findsNWidgets(2));
      expect(analyzer.requests, 2, reason: 'only the opened pair');
      // Dragging the outgoing waveform moves its exit point.
      await tester.dragFrom(
        tester.getTopLeft(find.byType(MixTimeline)) + const Offset(60, 40),
        const Offset(-40, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('3:11.3'), findsNothing);
      expect(tester.takeException(), isNull);
      final auto = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Automatic'),
      );
      expect(auto.selected, isFalse);
      // Optional review artifacts, produced by the same layout tests.
      if (Platform.environment['MIX_RENDER_DIR'] case final String directory) {
        await tester.ensureVisible(find.text('Noite Clara'));
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('mix-editor-shot')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File('$directory/editor-${size.width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('Mix page navigates pairs and retains drafts at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      userCustomPlaylists.value = [
        {
          'ytid': 'customId-mix-test',
          'title': 'Noites de verão',
          'source': 'user-created',
          'list': [
            _a,
            _b,
            {..._a, 'ytid': 'c', 'title': 'Horizonte'},
          ],
        },
      ];
      await tester.pumpWidget(
        localizedApp(
          const RepaintBoundary(
            key: ValueKey('mix-page-shot'),
            child: MixPage(playlist: 'customId-mix-test', song: _a, next: _b),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Melt'));
      await tester.tap(find.text('Melt'));
      await tester.tap(find.byTooltip('Next transition'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Previous transition'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Melt'))
            .selected,
        isTrue,
      );
      if (Platform.environment['MIX_RENDER_DIR'] case final String directory) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('mix-page-shot')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$directory/page-${size.width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

  testWidgets(
    'eight bars grows the overlap backwards without moving its exit',
    (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Transition duration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('8 bars').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save transition'));
      await tester.pumpAndSettle();
      final edit = mixEdits.get('p', 'a', 'b')!;
      expect(edit.length, const Duration(seconds: 16));
      expect(edit.outStart + edit.length, const Duration(milliseconds: 198000));
    },
  );

  testWidgets('thirty-two bars is longer than 40 s and is kept', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Transition duration'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('32 bars').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save transition'));
    await tester.pumpAndSettle();
    expect(mixEdits.get('p', 'a', 'b')!.length, const Duration(seconds: 64));
  });

  testWidgets(
    'saving a preset persists this ordered pair and refreshes preloading',
    (tester) async {
      await open(tester);
      await tester.ensureVisible(find.text('Melt'));
      await tester.tap(find.text('Melt'));
      await tester.tap(find.text('Save transition'));
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(mixEdits.get('p', 'a', 'b')!.style, MixStyle.melt);
      expect(mixEdits.get('p', 'b', 'a'), isNull);
      expect(handler.refreshes, 1);
    },
  );

  testWidgets('a transition stays out of a skipped opening', (tester) async {
    handler.opening = const [(start: 0, end: 10000)];
    await open(tester);
    await tester.ensureVisible(find.text('Melt'));
    await tester.tap(find.text('Melt'));
    // Dragging the incoming song back cannot bring the skipped part in.
    await tester.dragFrom(
      tester.getCenter(find.byType(MixTimeline)) + const Offset(60, 70),
      const Offset(300, 0),
    );
    await tester.tap(find.text('Save transition'));
    await tester.pumpAndSettle();
    expect(
      mixEdits.get('p', 'a', 'b')!.inStart,
      greaterThanOrEqualTo(const Duration(seconds: 10)),
    );
  });

  testWidgets('dragging a waveform puts the window on a bar of that song', (
    tester,
  ) async {
    await open(tester);
    final centre = tester.getCenter(find.byType(MixTimeline));
    // Slowly, so that no single step of the drag reaches the next bar.
    for (final lane in [const Offset(60, -70), const Offset(60, 70)]) {
      final gesture = await tester.startGesture(centre + lane);
      for (var i = 0; i < 30; i++) {
        await gesture.moveBy(const Offset(-3, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
    }
    await tester.tap(find.text('Save transition'));
    await tester.pumpAndSettle();
    final edit = mixEdits.get('p', 'a', 'b')!;
    // 120 beats a minute: a bar is 2 s; the ends' grids start at 160 s and 0.5 s.
    expect((edit.outStart.inMilliseconds - 160000) % 2000, 0);
    expect((edit.inStart.inMilliseconds - 500) % 2000, 0);
  });

  testWidgets('saving Automatic removes a previous customization', (
    tester,
  ) async {
    await mixEdits.set(
      'p',
      'a',
      'b',
      const MixEdit(
        outStart: Duration(seconds: 192),
        inStart: Duration(seconds: 1),
        length: Duration(seconds: 8),
        style: MixStyle.wave,
      ),
    );
    await open(tester);
    await tester.ensureVisible(find.text('Automatic'));
    await tester.tap(find.text('Automatic'));
    await tester.tap(find.text('Save transition'));
    await tester.pumpAndSettle();
    expect(mixEdits.get('p', 'a', 'b'), isNull);
  });

  testWidgets(
    'unavailable waveforms leave manual edits and preview available',
    (tester) async {
      analyzer.fail = true;
      await open(tester);
      expect(find.textContaining('Waveforms unavailable'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, FluentIcons.play_24_filled),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Transition duration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('12 s'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save transition'));
      await tester.pumpAndSettle();
      expect(mixEdits.get('p', 'a', 'b')!.length, const Duration(seconds: 12));
    },
  );

  testWidgets('a song saved without a duration gets it from its analysis', (
    tester,
  ) async {
    await open(tester, song: const {'ytid': 'a', 'title': 'Unknown'});
    expect(find.textContaining('Play these songs first'), findsNothing);
    expect(find.text('3:20.0'), findsNWidgets(2));
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Save transition'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('analysis preserves saved cue points when duration was unknown', (
    tester,
  ) async {
    const edit = MixEdit(
      outStart: Duration(seconds: 180),
      inStart: Duration(seconds: 30),
      length: Duration(seconds: 16),
      style: MixStyle.blend,
    );
    await mixEdits.set('p', 'a', 'b', edit);
    await open(tester, song: const {'ytid': 'a', 'title': 'Unknown'});
    final cue = tester.widget<MixTimeline>(find.byType(MixTimeline)).cue;
    expect(cue.outStart, edit.outStart);
    expect(cue.inStart, edit.inStart);
    expect(cue.length, edit.length);
  });

  testWidgets(
    'unknown duration disables editing instead of offering a fake timeline',
    (tester) async {
      analyzer.fail = true;
      await open(tester, song: const {'ytid': 'a', 'title': 'Unknown'});
      expect(find.textContaining('Play these songs first'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Save transition'),
            )
            .onPressed,
        isNull,
      );
    },
  );
}
