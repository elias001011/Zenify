import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/equalizer_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings(inMemory: true);

  final l10n = lookupAppLocalizations(const Locale('en'));

  /// The page on the desktop, with every band in view.
  void desktopTest(
    String name,
    Future<void> Function(WidgetTester tester) body, {
    List<double> saved = const [],
  }) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        tester.view.physicalSize = const Size(1200, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        equalizerEnabled.value = false;
        equalizerBandGains.value = saved;
        audioHandler = MusifyAudioHandler();
        await tester.pumpWidget(localizedApp(const EqualizerPage()));
        await tester.pumpAndSettle();
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  List<double> sliderValues(WidgetTester tester) => [
    for (final slider in tester.widgetList<Slider>(find.byType(Slider)))
      slider.value,
  ];

  desktopTest('shows the five bands in a range of 15 dB each way', (
    tester,
  ) async {
    expect(find.text(l10n.equalizerInitFailed), findsNothing);
    for (final frequency in [
      '60 Hz',
      '230 Hz',
      '910 Hz',
      '3.6 kHz',
      '14 kHz',
    ]) {
      expect(find.text(frequency), findsOneWidget);
    }
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders, hasLength(5));
    expect(sliders.map((s) => s.min), everyElement(-15));
    expect(sliders.map((s) => s.max), everyElement(15));
    expect(sliderValues(tester), everyElement(0));
  });

  desktopTest('opens on the saved gains', (tester) async {
    expect(sliderValues(tester), [3, -4, 0, 6, 1]);
  }, saved: const [3, -4, 0, 6, 1]);

  desktopTest('moving a band stores its gain', (tester) async {
    await tester.drag(find.byType(Slider).first, const Offset(100, 0));
    await tester.pumpAndSettle();

    final stored = equalizerBandGains.value;
    expect(stored, hasLength(5));
    expect(stored.first, greaterThan(0));
    expect(stored.skip(1), everyElement(0));
    expect(sliderValues(tester).first, stored.first);
    expect(Hive.box('settings').get('equalizerBandGains'), stored);
  });

  desktopTest('a preset sets the gains of all the bands', (tester) async {
    await tester.tap(find.text(l10n.equalizerPresetBassBoost));
    await tester.pumpAndSettle();

    expect(equalizerBandGains.value, [8, 8, 3, -2, -2]);
    expect(sliderValues(tester), [8, 8, 3, -2, -2]);
  });

  desktopTest('the switch turns the equalizer on and off and keeps it', (
    tester,
  ) async {
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(equalizerEnabled.value, isTrue);
    expect(Hive.box('settings').get('equalizerEnabled'), isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text(l10n.equalizerEnabledHint), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(equalizerEnabled.value, isFalse);
    expect(Hive.box('settings').get('equalizerEnabled'), isFalse);
  });

  desktopTest('reset brings every band back to zero', (tester) async {
    await tester.tap(find.byTooltip(l10n.equalizerResetBands));
    await tester.pumpAndSettle();

    expect(equalizerBandGains.value, [0, 0, 0, 0, 0]);
    expect(Hive.box('settings').get('equalizerBandGains'), [0, 0, 0, 0, 0]);
    expect(sliderValues(tester), everyElement(0));
  }, saved: const [3, -4, 0, 6, 1]);

  testWidgets('the settings route opens the page on the desktop', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      audioHandler = MusifyAudioHandler();
      NavigationManager();
      NavigationManager.router.go('/settings/equalizer');
      await tester.pumpWidget(
        MaterialApp.router(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: NavigationManager.router,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(EqualizerPage), findsOneWidget);
      expect(find.byType(Slider), findsWidgets);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
