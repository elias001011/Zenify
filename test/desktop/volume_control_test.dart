import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/localization/app_localizations_en.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_service.dart';
import 'package:musify/widgets/desktop_volume_control.dart';
import 'package:musify/widgets/mini_player.dart';
import 'package:musify/widgets/now_playing/player_actions.dart';

import '../support/app_harness.dart';

class _Handler extends MusifyAudioHandler {
  final changes = StreamController<double>.broadcast();
  double value = 0.5;
  @override
  double get volume => value;
  @override
  Stream<double> get volumeStream => changes.stream;
  @override
  Stream<List<Map>> get queueAsMapStream => Stream.value([
    {'ytid': 'test'},
  ]);
  @override
  Future<void> setVolume(double next) async {
    value = next;
    changes.add(next);
  }
}

class _VolumeLocalizations extends AppLocalizationsEn {
  @override
  String get volume => 'Localized volume';
}

class _VolumeDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _VolumeDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';
  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(_VolumeLocalizations());
  @override
  bool shouldReload(_VolumeDelegate old) => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  useAppSettings();
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    audioHandler = _Handler();
    await audioHandler.setVolume(0.5);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    debugDefaultTargetPlatformOverride = null;
  });
  tearDown(() async {
    unawaited((audioHandler as _Handler).changes.close());
    await audioHandler.audioPlayer.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: [
        const _VolumeDelegate(),
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const Scaffold(body: Center(child: DesktopVolumeControl())),
    ),
  );

  testWidgets(
    'desktop control is a filled pill that publishes volume changes',
    (tester) async {
      await mount(tester);
      final colors = Theme.of(tester.element(find.byType(Slider))).colorScheme;
      final size = tester.getSize(find.byType(DesktopVolumeControl));
      expect(size.width, DesktopVolumeControl.thickness);
      expect(size.height, DesktopVolumeControl.defaultLength);
      final slider = tester.widget<Slider>(find.byType(Slider));
      final theme = SliderTheme.of(tester.element(find.byType(Slider)));
      expect(theme.trackHeight, DesktopVolumeControl.thickness);
      expect(theme.activeTrackColor, colors.onSurface);
      expect(theme.inactiveTrackColor, colors.surfaceContainerHighest);
      expect(theme.thumbShape, SliderComponentShape.noThumb);
      expect(find.byTooltip('Localized volume'), findsOneWidget);
      slider.onChanged!(0.75);
      await tester.pumpAndSettle();
      expect(audioHandler.volume, 0.75);

      await audioHandler.setVolume(0.25);
      await tester.pumpAndSettle();

      expect(tester.widget<Slider>(find.byType(Slider)).value, 0.25);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'tapping or dragging the bar sets the volume, the speaker mutes',
    (tester) async {
      await mount(tester);
      final bar = tester.getRect(find.byType(DesktopVolumeControl));
      // Upright: the volume grows from the bottom.
      Offset at(double volume) =>
          Offset(bar.center.dx, bar.bottom - bar.height * volume);
      await tester.tapAt(at(0.8));
      await tester.pumpAndSettle();
      expect(audioHandler.volume, closeTo(0.8, 0.02));
      await tester.dragFrom(at(0.8), Offset(0, bar.height * 0.4));
      await tester.pumpAndSettle();
      expect(audioHandler.volume, closeTo(0.4, 0.05));

      final speaker = find.byTooltip('Localized volume');
      await tester.tap(speaker);
      await tester.pumpAndSettle();
      expect(audioHandler.volume, 0);
      await tester.tap(speaker);
      await tester.pumpAndSettle();
      expect(audioHandler.volume, closeTo(0.4, 0.05));
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'wheel adjusts current volume and clamps both ends',
    (tester) async {
      await mount(tester);
      final center = tester.getCenter(find.byType(Slider));
      Future<void> scroll(double delta) async {
        await tester.sendEventToBinding(
          PointerScrollEvent(position: center, scrollDelta: Offset(0, delta)),
        );
        await tester.pumpAndSettle();
      }

      await scroll(-20);
      expect(audioHandler.volume, closeTo(0.55, 0.0001));
      await scroll(20);
      expect(audioHandler.volume, closeTo(0.5, 0.0001));
      for (var i = 0; i < 20; i++) {
        await scroll(-1);
      }
      expect(audioHandler.volume, closeTo(0.55, 0.0001));
      await scroll(20);
      expect(audioHandler.volume, closeTo(0.5, 0.0001));
      await audioHandler.setVolume(1);
      await scroll(-20);
      expect(audioHandler.volume, 1);
      await audioHandler.setVolume(0);
      await scroll(20);
      expect(audioHandler.volume, 0);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform keeps the desktop control hidden', (tester) async {
      await mount(tester);
      expect(find.byType(Tooltip), findsNothing);
      expect(find.byType(Slider), findsNothing);
    }, variant: TargetPlatformVariant.only(platform));
  }
  testWidgets(
    'a radio station only offers the sleep timer and like',
    (tester) async {
      await tester.pumpWidget(
        localizedApp(
          Scaffold(
            body: Center(
              child: PlayerActions(
                metadata: const MediaItem(
                  id: 'radio',
                  title: 'Radio',
                  extras: {'isLive': true, 'ytid': 'radio'},
                ),
                onPanel: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(IconButton), findsNWidgets(2));
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'the player volume opens above its button, adjusts and restores mute',
    (tester) async {
      await tester.pumpWidget(
        localizedApp(
          Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: PlayerActions(
                metadata: const MediaItem(
                  id: 'test',
                  title: 'Song',
                  extras: {'ytid': 'test'},
                ),
                onPanel: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Slider), findsNothing);

      final opener = find.byTooltip('Volume');
      final openerRect = tester.getRect(opener);
      await tester.tap(opener);
      await tester.pumpAndSettle();
      final slider = find.byType(Slider);
      expect(slider, findsOneWidget);
      // A thin bar, centred right above the button.
      final bar = tester.getRect(find.byType(DesktopVolumeControl));
      expect(bar.width, DesktopVolumeControl.thickness);
      expect(bar.height, DesktopVolumeControl.defaultLength);
      expect(bar.center.dx, closeTo(openerRect.center.dx, 1));
      expect(openerRect.top - bar.bottom, inInclusiveRange(4, 16));

      final mute = find.descendant(
        of: find.byType(DesktopVolumeControl),
        matching: find.byType(Tooltip),
      );
      await tester.tap(mute);
      await tester.pumpAndSettle();
      expect(audioHandler.volume, 0);
      await tester.tap(mute);
      await tester.pumpAndSettle();
      expect(audioHandler.volume, 0.5);

      final center = tester.getCenter(slider);
      await tester.sendEventToBinding(
        PointerScrollEvent(position: center, scrollDelta: const Offset(0, 20)),
      );
      await tester.pumpAndSettle();
      expect(audioHandler.volume, closeTo(0.45, 0.0001));
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'separate controls share volume and mute restoration',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [
            _VolumeDelegate(),
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [DesktopVolumeControl(), DesktopVolumeControl()],
            ),
          ),
        ),
      );
      final buttons = find.byType(Tooltip);
      tester.widget<Slider>(find.byType(Slider).first).onChanged!(0.35);
      await tester.pumpAndSettle();
      expect(tester.widget<Slider>(find.byType(Slider).last).value, 0.35);
      await tester.tap(buttons.first);
      await tester.pumpAndSettle();
      expect(audioHandler.volume, 0);
      await tester.tap(buttons.last);
      await tester.pumpAndSettle();
      expect(audioHandler.volume, 0.35);
      expect(tester.widget<Slider>(find.byType(Slider).first).value, 0.35);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );

  testWidgets('collapsed volume and popup fit a 400 px mini player', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const item = MediaItem(id: 'test', title: 'Song', artist: 'Artist');
    audioHandler.mediaItem.add(item);
    audioHandler.queue.add([item, const MediaItem(id: 'next', title: 'Next')]);
    audioHandler.playbackState.add(
      PlaybackState(processingState: AudioProcessingState.ready, queueIndex: 0),
    );
    await tester.pumpWidget(
      localizedApp(
        const Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MiniPlayer(),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(DesktopVolumeButton), findsOneWidget);
    await tester.tap(find.byType(DesktopVolumeButton));
    await tester.pumpAndSettle();
    expect(find.byType(Slider), findsOneWidget);
    final bounds = tester.getRect(find.byType(Slider));
    expect(bounds.left, greaterThanOrEqualTo(0));
    expect(bounds.right, lessThanOrEqualTo(400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
