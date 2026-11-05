import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/models/position_data.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/widgets/app_motion.dart';
import 'package:musify/widgets/mini_player.dart';
import 'package:musify/widgets/position_slider.dart';

/// A player that stopped: it knows where it is, but emits nothing.
class _Handler extends MusifyAudioHandler {
  final positions = StreamController<PositionData>.broadcast();
  Duration at = const Duration(seconds: 4);

  @override
  PositionData get currentPositionData =>
      PositionData(at, Duration.zero, const Duration(hours: 2));

  @override
  Stream<PositionData> get positionDataStream => positions.stream;
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('zenify_position_resume');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box);
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<_Handler> pumpApp(WidgetTester tester, Widget child) async {
    final handler = _Handler();
    audioHandler = handler;
    addTearDown(handler.positions.close);
    final binding = tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(
      () => binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AppMotion(child: child)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    return handler;
  }

  /// The screen goes off, the song moves on and the player stops without
  /// sending anything, and then the screen comes back.
  Future<void> sleepAndWake(WidgetTester tester, _Handler handler) async {
    final binding = tester.binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    handler.at = const Duration(hours: 1);
    await tester.pump(const Duration(seconds: 5));
    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the bar shows the real position when the screen comes back', (
    tester,
  ) async {
    final handler = await pumpApp(tester, const PositionSlider());
    expect(find.text('00:04'), findsOneWidget);

    await sleepAndWake(tester, handler);

    expect(find.text('01:00:00'), findsOneWidget);
    expect(find.text('00:04'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  /// How far the ring has gone, from 0 to 1.
  double ringProgress(WidgetTester tester) {
    final ring = tester.widget<CustomPaint>(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter.runtimeType.toString() == '_CircularProgressPainter',
      ),
    );
    return (ring.painter! as dynamic).progress as double;
  }

  Future<_Handler> pumpMini(WidgetTester tester) async {
    final handler = await pumpApp(tester, const MiniPlayer());
    handler.mediaItem.add(const MediaItem(id: 'a', title: 'Song'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(ringProgress(tester), lessThan(0.01));
    return handler;
  }

  testWidgets('the ring shows the real position when the screen comes back', (
    tester,
  ) async {
    final handler = await pumpMini(tester);

    await sleepAndWake(tester, handler);

    expect(ringProgress(tester), closeTo(0.5, 0.01));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('the ring shows the real position when the full player closes', (
    tester,
  ) async {
    final handler = await pumpMini(tester);
    final navigator = Navigator.of(tester.element(find.byType(MiniPlayer)));

    // A screen over the mini player stops its tickers, as the full player does.
    unawaited(
      navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    handler.at = const Duration(hours: 1);
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(ringProgress(tester), closeTo(0.5, 0.01));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}
