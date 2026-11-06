import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/now_playing_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/widgets/mini_player.dart';
import 'package:musify/widgets/now_playing/now_playing_controls.dart';
import 'package:musify/widgets/playback_icon_button.dart';
import 'package:musify/widgets/position_slider.dart';

import 'support/app_harness.dart';

class _Handler extends MusifyAudioHandler {
  @override
  bool get hasNext => true;
  @override
  bool get hasPrevious => true;
}

const _song = MediaItem(
  id: 'song',
  title: 'A Song',
  artist: 'An Artist',
  duration: Duration(minutes: 3),
  extras: {'ytid': 'song'},
);

const _station = MediaItem(
  id: 'station',
  title: 'A Station',
  extras: {'ytid': 'station', 'isLive': true},
);

Widget _app(String locale, Widget home) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  useAppSettings();

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  Future<void> mount(
    WidgetTester tester,
    String locale,
    Widget home, {
    Size size = const Size(390, 844),
    MediaItem item = _song,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    audioHandler = _Handler();
    // Its own first updates would otherwise replace the state set below.
    await tester.pump(const Duration(milliseconds: 400));
    audioHandler.mediaItem.add(item);
    audioHandler.queue.add([item, _song]);
    audioHandler.playbackState.add(
      PlaybackState(
        playing: true,
        processingState: AudioProcessingState.ready,
        queueIndex: 0,
      ),
    );
    await tester.pumpWidget(_app(locale, home));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> unmount(WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = null;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  final previous = find.byIcon(FluentIcons.previous_24_filled);
  final next = find.byIcon(FluentIcons.next_24_filled);
  final play = find.byType(PlaybackIconButton);

  // Media controls keep their order and direction in a right-to-left
  // language: previous on the left, next on the right, as on any player.
  void expectTransportOrder(
    WidgetTester tester, {
    required bool modes,
    bool outward = false,
  }) {
    final x = (Finder finder) => tester.getCenter(finder).dx;
    expect(x(previous), lessThan(x(play)));
    expect(x(play), lessThan(x(next)));
    expect(
      Directionality.of(tester.element(previous)),
      TextDirection.ltr,
      reason: 'the arrows and their nudge are drawn left to right',
    );
    if (modes) {
      final shuffle = find.byType(PlaybackModeButton).first;
      final repeat = find.byType(PlaybackModeButton).last;
      expect(x(shuffle), lessThan(x(previous)));
      expect(x(next), lessThan(x(repeat)));
    }
    if (outward) {
      // The player moves them out beyond its progress bar, so their icons
      // line up with it.
      final bar = tester.getRect(find.byType(PositionSlider));
      expect(
        tester.getRect(find.byType(PlaybackModeButton).first).left,
        lessThan(bar.left),
      );
      expect(
        tester.getRect(find.byType(PlaybackModeButton).last).right,
        greaterThan(bar.right),
      );
    }
  }

  for (final locale in ['en', 'he']) {
    for (final size in const [Size(390, 844), Size(1280, 800)]) {
      testWidgets('the player\'s buttons keep their order ($locale, $size)', (
        tester,
      ) async {
        await mount(tester, locale, const NowPlayingPage(), size: size);
        expectTransportOrder(tester, modes: true, outward: true);
        await unmount(tester);
      });
    }

    testWidgets('a station\'s buttons keep their order ($locale)', (
      tester,
    ) async {
      await mount(tester, locale, const NowPlayingPage(), item: _station);
      expectTransportOrder(tester, modes: false);
      await unmount(tester);
    });

    testWidgets('the desktop mini player keeps its order ($locale)', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await mount(
        tester,
        locale,
        const Scaffold(body: MiniPlayer(wide: true)),
        size: const Size(1280, 800),
      );
      expectTransportOrder(tester, modes: true);
      await unmount(tester);
    });

    testWidgets('the phone mini player keeps play before next ($locale)', (
      tester,
    ) async {
      await mount(tester, locale, const Scaffold(body: MiniPlayer()));
      final pause = find.byIcon(FluentIcons.pause_16_filled);
      expect(next, findsOneWidget);
      expect(tester.getCenter(pause).dx, lessThan(tester.getCenter(next).dx));
      await unmount(tester);
    });
  }
}
