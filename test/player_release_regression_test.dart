import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/now_playing_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/desktop_volume_control.dart';
import 'package:musify/widgets/marquee.dart';
import 'package:musify/widgets/now_playing/now_playing_artwork.dart';
import 'package:musify/widgets/now_playing/player_actions.dart';
import 'package:musify/widgets/now_playing/wave_visualizer.dart';
import 'package:musify/widgets/queue_list_view.dart';

class _Handler extends MusifyAudioHandler {
  @override
  Stream<List<Map>> get queueAsMapStream => Stream.value([
    {'ytid': 'test', 'title': 'Song'},
  ]);
  @override
  double get volume => 0.4;
  @override
  Stream<double> get volumeStream => Stream.value(0.4);
}

const songA = MediaItem(id: 'a', title: 'Song A', extras: {'ytid': 'a'});
const songB = MediaItem(id: 'b', title: 'Song B', extras: {'ytid': 'b'});
Widget app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('zenify_player_release');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box, bytes: Uint8List(0));
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  setUp(() {
    audioHandler = _Handler();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('actions follow the new song while the player remains open', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    userLikedSongsList.value = [
      {'ytid': 'a', 'title': 'Song A'},
    ];
    Widget actions(MediaItem item) =>
        app(PlayerActions(metadata: item, panel: null, onPanel: (_, _) {}));
    await tester.pumpWidget(actions(songA));
    await tester.pump();
    expect(find.byIcon(FluentIcons.heart_24_filled), findsOneWidget);
    await tester.pumpWidget(actions(songB));
    await tester.pump();
    expect(find.byIcon(FluentIcons.heart_24_regular), findsOneWidget);
    await tester.tap(find.byTooltip('Liked songs'));
    await tester.pump();
    expect(
      userLikedSongsList.value.map((s) => s['ytid']),
      containsAll(['a', 'b']),
    );
    expect(find.byType(DesktopVolumeButton), findsNothing);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'visualizer preference survives reopening and artwork never grows during switch',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.runAsync(() => setPlayerVisualizer(false));
      final artwork = app(
        const Center(child: NowPlayingArtwork(metadata: songA, size: 240)),
      );
      await tester.pumpWidget(artwork);
      await tester.tap(find.byType(NowPlayingArtwork));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        tester.getSize(find.byType(NowPlayingArtwork)),
        const Size(240, 240),
      );
      expect(showPlayerVisualizer.value, isTrue);
      expect(Hive.box('settings').get('showPlayerVisualizer'), isTrue);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(artwork);
      expect(find.byType(WaveVisualizer), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'wide Android has no volume button; desktop queue has no close header',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      audioHandler.mediaItem.add(songA);
      await tester.pumpWidget(app(const NowPlayingPage()));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.byType(DesktopVolumeButton), findsNothing);
      await tester.tap(find.byTooltip('Queue'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(QueueWidget), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      await tester.tap(find.byTooltip('Queue'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(QueueWidget), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('desktop popup stays within the viewport at the bottom right', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(
      app(
        const Align(
          alignment: Alignment.bottomRight,
          child: DesktopVolumeButton(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(DesktopVolumeButton));
    await tester.pump(const Duration(milliseconds: 200));
    final rect = tester.getRect(find.byType(DesktopVolumeControl));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(800));
    expect(rect.bottom, lessThanOrEqualTo(600));
    expect(find.byType(Slider), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('closing scrolling text cancels the pause and animation work', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const Center(
          child: SizedBox(
            width: 60,
            child: MarqueeWidget(
              pauseDuration: Duration(milliseconds: 200),
              child: Text(
                'A long title that must scroll across the small viewport',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 210));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
