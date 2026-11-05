import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/now_playing_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/mini_player.dart';
import 'package:musify/widgets/now_playing/now_playing_artwork.dart';
import 'package:musify/widgets/now_playing/now_playing_controls.dart';
import 'package:musify/widgets/playback_icon_button.dart';
import 'package:musify/widgets/position_slider.dart';

import 'support/app_harness.dart';

/// Answers for the stations around the one that plays, and counts the skips.
class _Handler extends MusifyAudioHandler {
  _Handler({this.next = true, this.previous = true});

  bool next;
  bool previous;
  int skippedToNext = 0;
  int skippedToPrevious = 0;

  @override
  bool get hasNext => next;
  @override
  bool get hasPrevious => previous;
  @override
  bool get canSkipToNext => next;

  @override
  Future<void> skipToNext({bool playWhenReady = true}) async => skippedToNext++;
  @override
  Future<void> skipToPrevious({bool playWhenReady = true}) async =>
      skippedToPrevious++;
}

const _station = MediaItem(
  id: 'r2',
  title: 'Station Two',
  artist: 'Genre',
  extras: {'ytid': 'r2', 'isLive': true},
);

const _song = MediaItem(
  id: 'song',
  title: 'A Song',
  artist: 'An Artist',
  duration: Duration(minutes: 3),
  extras: {'ytid': 'song'},
);

IconButton _button(String tooltip) =>
    find
            .byWidgetPredicate((w) => w is IconButton && w.tooltip == tooltip)
            .evaluate()
            .single
            .widget
        as IconButton;

void main() {
  useAppSettings();

  Future<_Handler> mountPlayer(
    WidgetTester tester,
    Size size, {
    bool next = true,
    bool previous = true,
    MediaItem item = _station,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handler = _Handler(next: next, previous: previous);
    audioHandler = handler;
    // Its own first updates would otherwise replace the state set below.
    await tester.pump(const Duration(milliseconds: 400));
    handler.mediaItem.add(item);
    handler.queue.add([item]);
    handler.playbackState.add(
      PlaybackState(playing: true, processingState: AudioProcessingState.ready),
    );
    await tester.pumpWidget(localizedApp(const NowPlayingPage()));
    await tester.pump(const Duration(milliseconds: 400));
    return handler;
  }

  Future<void> unmount(WidgetTester tester) async {
    // Reset in the test, as the binding checks it before the teardowns run.
    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  for (final size in const [Size(390, 844), Size(360, 740), Size(1280, 800)]) {
    testWidgets('the player of a radio station has previous, play and next '
        'and no progress bar ($size)', (tester) async {
      final handler = await mountPlayer(tester, size);

      expect(find.byType(NowPlayingArtwork), findsOneWidget);
      expect(find.byType(NowPlayingTitle), findsNothing);
      expect(find.byIcon(FluentIcons.previous_24_filled), findsOneWidget);
      expect(find.byIcon(FluentIcons.next_24_filled), findsOneWidget);
      expect(find.byType(PlaybackIconButton), findsOneWidget);
      expect(find.byTooltip('Pause'), findsOneWidget);
      expect(find.byType(PositionSlider), findsNothing);
      expect(find.byType(PlaybackModeButton), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Skip to next'));
      await tester.pump();
      expect(handler.skippedToNext, 1);
      expect(handler.skippedToPrevious, 0);
      await tester.tap(find.byTooltip('Skip to previous'));
      await tester.pump();
      expect(handler.skippedToPrevious, 1);
      await tester.pump(const Duration(seconds: 1));

      await unmount(tester);
    });
  }

  testWidgets('the buttons are placed where the song transport would be', (
    tester,
  ) async {
    await mountPlayer(tester, const Size(390, 844));
    final radio = tester.getRect(find.byType(PlaybackTransportControls));
    // Centred under the cover, near the bottom, above the action bar.
    expect(radio.center.dx, closeTo(195, 1));
    expect(radio.bottom, greaterThan(844 * 0.6));
    final cover = tester.getRect(find.byType(NowPlayingArtwork));
    expect(radio.top, greaterThanOrEqualTo(cover.bottom));
    await unmount(tester);
  });

  testWidgets('on its side, the buttons are centred beside the cover', (
    tester,
  ) async {
    await mountPlayer(tester, const Size(844, 390));
    expect(find.byIcon(FluentIcons.previous_24_filled), findsOneWidget);
    expect(find.byIcon(FluentIcons.next_24_filled), findsOneWidget);
    expect(find.byType(PlaybackIconButton), findsOneWidget);
    expect(find.byType(PositionSlider), findsNothing);
    final cover = tester.getRect(find.byType(NowPlayingArtwork));
    final controls = tester.getRect(find.byType(PlaybackTransportControls));
    expect(controls.left, greaterThan(cover.right));
    expect(controls.center.dy, closeTo(cover.center.dy, 40));
    expect(tester.takeException(), isNull);
    await unmount(tester);
  });

  for (final size in const [Size(390, 844), Size(1280, 800)]) {
    testWidgets(
      'without a list the buttons of a station are disabled ($size)',
      (tester) async {
        final handler = await mountPlayer(
          tester,
          size,
          next: false,
          previous: false,
        );
        // Even with a repeat mode on, which has no meaning for a station.
        repeatNotifier.value = AudioServiceRepeatMode.all;
        addTearDown(() => repeatNotifier.value = AudioServiceRepeatMode.none);
        await tester.pump();

        expect(_button('Skip to next').onPressed, isNull);
        expect(_button('Skip to previous').onPressed, isNull);
        await tester.tap(find.byTooltip('Skip to next'), warnIfMissed: false);
        await tester.pump();
        expect(handler.skippedToNext, 0);
        expect(_button('Pause').onPressed, isNotNull);
        await unmount(tester);
      },
    );
  }

  testWidgets('a song keeps its progress bar, shuffle and repeat', (
    tester,
  ) async {
    final handler = await mountPlayer(
      tester,
      const Size(390, 844),
      item: _song,
    );
    expect(find.byType(PositionSlider), findsOneWidget);
    expect(find.byType(PlaybackModeButton), findsNWidgets(2));
    await tester.tap(find.byTooltip('Skip to next'));
    await tester.pump();
    expect(handler.skippedToNext, 1);
    await tester.pump(const Duration(seconds: 1));
    await unmount(tester);
  });

  testWidgets('the transport follows the station switching to a song', (
    tester,
  ) async {
    final handler = await mountPlayer(tester, const Size(390, 844));
    expect(find.byType(PositionSlider), findsNothing);

    handler.mediaItem.add(_song);
    handler.queue.add([_song]);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PositionSlider), findsOneWidget);
    expect(find.byType(PlaybackModeButton), findsNWidgets(2));

    handler.mediaItem.add(_station);
    handler.queue.add([_station]);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(PositionSlider), findsNothing);
    expect(find.byType(PlaybackModeButton), findsNothing);
    await unmount(tester);
  });

  group('the mini player of a radio station', () {
    Future<_Handler> mountMini(
      WidgetTester tester, {
      required bool wide,
      bool next = true,
      bool previous = true,
    }) async {
      tester.view.physicalSize = wide
          ? const Size(1280, 800)
          : const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      if (wide) debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final handler = _Handler(next: next, previous: previous);
      audioHandler = handler;
      // Its own first updates would otherwise replace the state set below.
      await tester.pump(const Duration(milliseconds: 400));
      handler.mediaItem.add(_station);
      handler.queue.add([_station]);
      handler.playbackState.add(
        PlaybackState(
          playing: true,
          processingState: AudioProcessingState.ready,
        ),
      );
      await tester.pumpWidget(
        localizedApp(Scaffold(body: MiniPlayer(wide: wide))),
      );
      await tester.pump(const Duration(milliseconds: 400));
      return handler;
    }

    testWidgets('wide: previous, pause and next, and no progress bar', (
      tester,
    ) async {
      final handler = await mountMini(tester, wide: true);

      expect(find.byType(PlaybackTransportControls), findsOneWidget);
      expect(find.byIcon(FluentIcons.previous_24_filled), findsOneWidget);
      expect(find.byIcon(FluentIcons.next_24_filled), findsOneWidget);
      expect(find.byTooltip('Pause'), findsOneWidget);
      expect(find.byType(PositionSlider), findsNothing);
      expect(find.byType(PlaybackModeButton), findsNothing);
      final play = tester.getSize(find.byTooltip('Pause'));
      expect(play.width, dockButtonSizes.box);

      await tester.tap(find.byTooltip('Skip to next'));
      await tester.pump();
      expect(handler.skippedToNext, 1);
      await tester.tap(find.byTooltip('Skip to previous'));
      await tester.pump();
      expect(handler.skippedToPrevious, 1);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('wide, with no list: the skip buttons are disabled', (
      tester,
    ) async {
      await mountMini(tester, wide: true, next: false, previous: false);
      expect(_button('Skip to next').onPressed, isNull);
      expect(_button('Skip to previous').onPressed, isNull);
      expect(_button('Pause').onPressed, isNotNull);
      await unmount(tester);
    });

    testWidgets('compact: Next shows when there is a station to skip to', (
      tester,
    ) async {
      final handler = await mountMini(tester, wide: false);

      expect(find.byIcon(FluentIcons.next_24_filled), findsOneWidget);
      // Previous exists only in the wide one, as for songs.
      expect(find.byIcon(FluentIcons.previous_24_filled), findsNothing);
      await tester.tap(find.byIcon(FluentIcons.next_24_filled));
      await tester.pump();
      expect(handler.skippedToNext, 1);
      await unmount(tester);
    });

    testWidgets('compact: no Next without a list', (tester) async {
      await mountMini(tester, wide: false, next: false);
      expect(find.byIcon(FluentIcons.next_24_filled), findsNothing);
      await unmount(tester);
    });
  });
}
