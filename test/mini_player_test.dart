import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/models/position_data.dart';
import 'package:musify/screens/now_playing_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/mini_player.dart';
import 'package:musify/widgets/now_playing/wave_visualizer.dart';
import 'package:musify/widgets/playback_icon_button.dart';
import 'package:musify/widgets/song_artwork.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings();

  Widget app(Key key) => localizedApp(Scaffold(body: MiniPlayer(key: key)));

  testWidgets('a mini player built later still shows the song', (tester) async {
    audioHandler = MusifyAudioHandler();
    audioHandler.mediaItem.add(
      const MediaItem(id: 'a', title: 'Song', extras: {'ytid': 'a'}),
    );
    audioHandler.playbackState.add(PlaybackState(playing: true));

    await tester.pumpWidget(app(const ValueKey(1)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Song'), findsOneWidget);

    // As when the shell moves it between the dock and the desktop rail.
    await tester.pumpWidget(app(const ValueKey(2)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Song'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
  testWidgets('the empty space beside the song opens the full player', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    audioHandler = MusifyAudioHandler();
    audioHandler.mediaItem.add(const MediaItem(id: 'short', title: 'A'));
    audioHandler.playbackState.add(PlaybackState(playing: true));
    await tester.pumpWidget(app(const ValueKey('tap-area')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    final rect = tester.getRect(find.byType(MiniPlayer));
    await tester.tapAt(Offset(rect.left + 200, rect.center.dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(NowPlayingPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets(
    'the mini player keeps its artwork while the player shows waves',
    (tester) async {
      audioHandler = MusifyAudioHandler();
      audioHandler.mediaItem.add(
        const MediaItem(id: 'a', title: 'Song', extras: {'ytid': 'a'}),
      );
      audioHandler.playbackState.add(PlaybackState(playing: true));
      showPlayerVisualizer.value = true;
      addTearDown(() => showPlayerVisualizer.value = false);

      await tester.pumpWidget(app(const ValueKey('waves')));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(WaveVisualizer), findsNothing);
      expect(find.byType(SongArtworkWidget), findsOneWidget);
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    },
  );

  group('Next on the compact mini player', () {
    Future<void> mount(
      WidgetTester tester,
      AudioServiceRepeatMode mode,
      Object key,
    ) async {
      repeatNotifier.value = mode;
      addTearDown(() => repeatNotifier.value = AudioServiceRepeatMode.none);
      audioHandler = MusifyAudioHandler();
      // Its own first updates would otherwise replace the state set below.
      await tester.pump(const Duration(milliseconds: 400));
      audioHandler.mediaItem.add(const MediaItem(id: 'b', title: 'B'));
      audioHandler.queue.add(const [
        MediaItem(id: 'a', title: 'A'),
        MediaItem(id: 'b', title: 'B'),
      ]);
      // The last of two songs.
      audioHandler.playbackState.add(
        PlaybackState(playing: true, queueIndex: 1),
      );
      await tester.pumpWidget(app(ValueKey(key)));
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<void> unmount(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    }

    testWidgets('shows on the last song while repeating all', (tester) async {
      await mount(tester, AudioServiceRepeatMode.all, 'repeat-all');
      expect(find.byIcon(FluentIcons.next_24_filled), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('is hidden on the last song when not repeating', (
      tester,
    ) async {
      await mount(tester, AudioServiceRepeatMode.none, 'repeat-none');
      expect(find.byIcon(FluentIcons.next_24_filled), findsNothing);
      await unmount(tester);
    });

    testWidgets('follows the repeat mode once mounted', (tester) async {
      await mount(tester, AudioServiceRepeatMode.none, 'repeat-switch');
      expect(find.byIcon(FluentIcons.next_24_filled), findsNothing);
      repeatNotifier.value = AudioServiceRepeatMode.all;
      await tester.pump();
      expect(find.byIcon(FluentIcons.next_24_filled), findsOneWidget);
      repeatNotifier.value = AudioServiceRepeatMode.none;
      await tester.pump();
      expect(find.byIcon(FluentIcons.next_24_filled), findsNothing);
      await unmount(tester);
    });
  });

  for (final platform in [TargetPlatform.linux, TargetPlatform.android]) {
    testWidgets('the compact ${platform.name} mini player has the ring', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      audioHandler = MusifyAudioHandler();
      audioHandler.mediaItem.add(const MediaItem(id: 'a', title: 'Song'));
      audioHandler.playbackState.add(PlaybackState(playing: true));

      await tester.pumpWidget(app(ValueKey(platform)));
      await tester.pump(const Duration(milliseconds: 400));

      // The same ring on every platform: the play button is drawn inside it,
      // and the position is followed by it alone.
      expect(find.byType(PlaybackIconButton), findsNothing);
      expect(find.byType(StreamBuilder<PositionData>), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    });
  }
}
