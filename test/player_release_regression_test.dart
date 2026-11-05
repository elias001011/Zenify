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
import 'package:musify/widgets/app_notice.dart';
import 'package:musify/widgets/desktop_volume_control.dart';
import 'package:musify/widgets/floating_surface.dart';
import 'package:musify/widgets/marquee.dart';
import 'package:musify/widgets/mini_player.dart';
import 'package:musify/widgets/now_playing/now_playing_artwork.dart';
import 'package:musify/widgets/now_playing/now_playing_controls.dart';
import 'package:musify/widgets/now_playing/player_actions.dart';
import 'package:musify/widgets/now_playing/wave_visualizer.dart';
import 'package:musify/widgets/playlist_page/playlist_header.dart';
import 'package:musify/widgets/position_slider.dart';
import 'package:musify/widgets/queue_list_view.dart';

class _Handler extends MusifyAudioHandler {
  _Handler() {
    queue.add([
      for (var i = 0; i < 6; i++)
        MediaItem(id: 'song$i', title: 'Track $i', extras: {'ytid': 'song$i'}),
    ]);
  }

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
    shuffleNotifier.value = false;
    repeatNotifier.value = AudioServiceRepeatMode.none;
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
        app(PlayerActions(metadata: item, onPanel: (_) {}));
    await tester.pumpWidget(actions(songA));
    await tester.pump();
    // The button to add to a playlist shows a liked song with a heart.
    expect(find.byIcon(FluentIcons.heart_24_filled), findsOneWidget);
    expect(find.byIcon(FluentIcons.album_add_24_regular), findsNothing);
    await tester.pumpWidget(actions(songB));
    await tester.pump();
    expect(find.byIcon(FluentIcons.album_add_24_regular), findsOneWidget);
    expect(find.byIcon(FluentIcons.heart_24_filled), findsNothing);
    // A song is liked from the dialog of that button, not by a heart of its own.
    expect(find.byTooltip('Liked songs'), findsNothing);
    await tester.tap(find.byTooltip('Add to playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Liked songs'));
    await tester.pumpAndSettle();
    expect(
      userLikedSongsList.value.map((s) => s['ytid']),
      containsAll(['a', 'b']),
    );
    expect(find.byIcon(FluentIcons.heart_24_filled), findsOneWidget);
    expect(find.byType(DesktopVolumeButton), findsNothing);
    AppNotices.dismiss();
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the add to playlist button can sit beside the song instead', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        PlayerActions(
          metadata: songA,
          onPanel: (_) {},
          showAddToPlaylist: false,
        ),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Add to playlist'), findsNothing);
    await tester.pumpWidget(app(const AddToPlaylistButton(metadata: songA)));
    await tester.pump();
    expect(find.byTooltip('Add to playlist'), findsOneWidget);
    // Nothing to add a radio station or a local file to.
    for (final item in [
      const MediaItem(
        id: 'r',
        title: 'Radio',
        extras: {'ytid': 'r', 'isLive': true},
      ),
      const MediaItem(
        id: 'l',
        title: 'Local',
        extras: {'ytid': 'local:/a.mp3'},
      ),
    ]) {
      await tester.pumpWidget(app(AddToPlaylistButton(metadata: item)));
      await tester.pump();
      expect(find.byTooltip('Add to playlist'), findsNothing);
    }
    await tester.pumpWidget(const SizedBox());
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
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
  testWidgets('volume opens upward even with free space below', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(app(const Center(child: DesktopVolumeButton())));
    final anchor = tester.getRect(find.byType(DesktopVolumeButton));
    await tester.tap(find.byType(DesktopVolumeButton));
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.getRect(find.byType(DesktopVolumeControl)).bottom,
      lessThan(anchor.top),
    );
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'compact player has the wide player\'s plain actions and buttons',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.physicalSize = const Size(420, 860);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        audioHandler.mediaItem.add(songA);
        await tester.pumpWidget(app(const NowPlayingPage()));
        await tester.pump(const Duration(milliseconds: 400));
        // No card around the actions: they sit on the page like the wide ones.
        expect(find.byType(FloatingSurface), findsNothing);
        expect(find.byTooltip('Queue'), findsOneWidget);
        for (final tooltip in ['Play', 'Shuffle']) {
          final button = tester.widget<IconButton>(
            find.byWidgetPredicate(
              (w) => w is IconButton && w.tooltip == tooltip,
            ),
          );
          expect(
            button.style!.backgroundColor!.resolve({}),
            Colors.transparent,
          );
        }
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('desktop mini uses shared transport and actions without panels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    audioHandler.mediaItem.add(songA);
    await tester.pumpWidget(app(const MiniPlayer(wide: true)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PlaybackTransportControls), findsOneWidget);
    expect(find.byType(PlayerActions), findsOneWidget);
    expect(find.byType(PlaybackModeButton), findsNWidgets(2));
    final playControl = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Play',
    );
    final playButton = tester.widget<IconButton>(playControl);
    // No filled circle behind it: the phone's mini player has none either.
    expect(playButton.style!.backgroundColor!.resolve({}), Colors.transparent);
    expect(playButton.style!.shape!.resolve({}), isA<CircleBorder>());
    expect(tester.getSize(playControl).width, dockButtonSizes.box);
    // The phone's progress bar, under the five buttons.
    expect(find.byType(PositionSlider), findsOneWidget);
    expect(find.byTooltip('Queue'), findsNothing);
    expect(find.byTooltip('Lyrics'), findsNothing);
    final bar = tester.getRect(find.byType(MiniPlayer));
    final controls = tester.getRect(find.byType(PlaybackTransportControls));
    expect(controls.center.dx, closeTo(bar.center.dx, 1));
    await tester.tap(find.byTooltip('Shuffle'));
    await tester.pump();
    expect(shuffleNotifier.value, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  for (final width in const [900.0, 1100.0]) {
    testWidgets(
      'desktop mini fits its five buttons and bar in ${width.toInt()}',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        debugDefaultTargetPlatformOverride = TargetPlatform.linux;
        audioHandler.mediaItem.add(songA);
        await tester.pumpWidget(app(const MiniPlayer(wide: true)));
        await tester.pump(const Duration(milliseconds: 400));
        final buttons = tester.getRect(find.byType(PlaybackTransportControls));
        final bar = tester.getRect(find.byType(PositionSlider));
        expect(bar.width, greaterThan(buttons.width));
        expect(bar.top, greaterThanOrEqualTo(buttons.bottom - 1));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('artist biography stays readable when expanded on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final description = List.filled(80, 'Artist biography.').join(' ');
    await tester.pumpWidget(
      app(
        PlaylistHeader(
          title: 'Artist',
          isArtist: true,
          description: description,
        ),
      ),
    );
    expect(
      tester.getSize(find.text(description)).width,
      lessThanOrEqualTo(860),
    );
    await tester.tap(find.text(description));
    await tester.pump();
    expect(
      tester.getSize(find.text(description)).width,
      lessThanOrEqualTo(860),
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop queue is directly on the canvas', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    audioHandler.mediaItem.add(songA);
    await tester.pumpWidget(app(const NowPlayingPage()));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byTooltip('Queue'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.ancestor(
        of: find.byType(QueueWidget),
        matching: find.byType(FloatingSurface),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  for (final size in [
    const Size(900, 560),
    const Size(1280, 720),
    const Size(1600, 900),
    const Size(1920, 1080),
  ]) {
    for (final scale in [1.0, 1.8]) {
      testWidgets(
        'desktop playback fits with the volume in the actions ($size, text $scale)',
        (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.linux;
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          audioHandler.mediaItem.add(songA);
          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: const [
                AppLocalizations.delegate,
                ...GlobalMaterialLocalizations.delegates,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(scale),
                ),
                child: const NowPlayingPage(),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 500));
          final cover = tester.getRect(find.byType(NowPlayingArtwork));
          final progress = tester.getRect(find.byType(PositionSlider));
          final title = tester.getRect(find.byType(NowPlayingTitle));
          expect(
            title.top - cover.bottom,
            inInclusiveRange(20, 20 + 40 * scale),
            reason:
                'The artwork must stay grouped with its title on tall windows',
          );
          // The phone's player: the song at the left, over the bar's edge.
          expect(title.left, closeTo(progress.left, 0.1));
          expect(cover.center.dx, closeTo(progress.center.dx, 0.1));
          expect(cover.width, lessThanOrEqualTo(progress.width));
          expect(
            find.ancestor(
              of: find.byType(NowPlayingArtwork),
              matching: find.byType(SingleChildScrollView),
            ),
            findsNothing,
            reason:
                'Playback must fit the viewport without scrolling the controls',
          );
          final play = tester.getCenter(
            find.byIcon(FluentIcons.play_24_filled),
          );
          for (final icon in [
            FluentIcons.previous_24_filled,
            FluentIcons.next_24_filled,
            FluentIcons.arrow_shuffle_24_regular,
            FluentIcons.arrow_repeat_all_24_regular,
          ]) {
            expect(
              tester.getCenter(find.byIcon(icon)).dy,
              closeTo(play.dy, 0.1),
            );
          }
          audioHandler.playbackState.add(
            PlaybackState(
              playing: true,
              processingState: AudioProcessingState.ready,
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          expect(
            tester.getCenter(find.byIcon(FluentIcons.pause_24_filled)).dy,
            closeTo(play.dy, 0.1),
          );
          // The volume is a button among the actions, like in every layout;
          // its bar only exists while it is open.
          expect(find.byType(DesktopVolumeControl), findsNothing);
          expect(
            find.descendant(
              of: find.byType(PlayerActions),
              matching: find.byType(DesktopVolumeButton),
            ),
            findsOneWidget,
          );
          expect(
            find.byType(DesktopVolumeButton).hitTestable(),
            findsOneWidget,
          );
          await tester.tap(find.byType(DesktopVolumeButton));
          await tester.pump(const Duration(milliseconds: 300));
          final bar = tester.getRect(find.byType(DesktopVolumeControl));
          expect(
            bar.bottom,
            lessThan(tester.getRect(find.byType(DesktopVolumeButton)).top),
          );
          expect(bar.left, greaterThanOrEqualTo(0));
          expect(bar.right, lessThanOrEqualTo(size.width));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }

  testWidgets('desktop panel closes visibly before it is removed', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    audioHandler.mediaItem.add(songA);
    await tester.pumpWidget(app(const NowPlayingPage()));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('Queue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Queue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(QueueWidget), findsOneWidget);
    final artDuringClose = tester.getCenter(find.byType(NowPlayingArtwork)).dx;
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(QueueWidget), findsNothing);
    expect(
      tester.getCenter(find.byType(NowPlayingArtwork)).dx,
      greaterThan(artDuringClose),
    );
    await tester.tap(find.byTooltip('Queue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(QueueWidget), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
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
