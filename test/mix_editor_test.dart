import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

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
    required Duration duration,
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
      await tester.ensureVisible(find.byType(Slider).last);
      await tester.drag(find.byType(Slider).last, const Offset(-30, 0));
      await tester.pumpAndSettle();
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
      await tester.ensureVisible(find.text('8 bars'));
      await tester.tap(find.text('8 bars'));
      await tester.tap(find.text('Save transition'));
      await tester.pumpAndSettle();
      final edit = mixEdits.get('p', 'a', 'b')!;
      expect(edit.length, const Duration(seconds: 16));
      expect(edit.outStart + edit.length, const Duration(milliseconds: 198000));
    },
  );

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
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Listen'),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown duration disables editing instead of offering a fake timeline',
    (tester) async {
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
      expect(analyzer.requests, 0);
    },
  );
}
