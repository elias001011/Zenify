import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/constants/app_constants.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' as app;
import 'package:musify/screens/settings_page.dart';
import 'package:musify/services/io_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/services/song_fade.dart';
import 'package:musify/widgets/custom_bar.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings(inMemory: true);

  final l10n = lookupAppLocalizations(const Locale('en'));

  tearDown(() {
    app.isFdroidBuild = false;
    offlineMode.value = false;
    useSystemColor.value = true;
  });

  Future<void> mount(WidgetTester tester, {Widget? wrap}) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(localizedApp(wrap ?? const SettingsPage()));
    await tester.pump();
  }

  Finder barFinder(String name) =>
      find.byWidgetPredicate((w) => w is CustomBar && w.tileName == name);

  CustomBar bar(WidgetTester tester, String name) =>
      tester.widget<CustomBar>(barFinder(name));

  group('Preferences card corners follow the offline switch', () {
    // The last bar of the Preferences card, if the card ends there: online,
    // it continues into the online features, which close it themselves.
    String? lastBar({required bool fdroid, required bool offline}) {
      if (!offline) return null;
      return fdroid ? l10n.offlineMode : l10n.automaticUpdateChecks;
    }

    void expectCorners(
      WidgetTester tester, {
      required bool fdroid,
      required bool offline,
    }) {
      final last = lastBar(fdroid: fdroid, offline: offline);
      final names = [l10n.offlineMode, if (!fdroid) l10n.automaticUpdateChecks];
      for (final name in names) {
        expect(
          bar(tester, name).borderRadius,
          name == last ? commonCustomBarRadiusLast : BorderRadius.zero,
          reason:
              '$name, offline=$offline, '
              '${fdroid ? 'F-Droid' : 'store'} build',
        );
      }
      expect(
        barFinder('SponsorBlock'),
        offline ? findsNothing : findsOneWidget,
      );
    }

    for (final fdroid in [false, true]) {
      for (final startOffline in [false, true]) {
        final build = fdroid ? 'F-Droid' : 'store';
        final from = startOffline ? 'on' : 'off';
        final to = startOffline ? 'off' : 'on';
        testWidgets('$build build, offline $from then $to', (tester) async {
          app.isFdroidBuild = fdroid;
          offlineMode.value = startOffline;
          await mount(tester);
          expectCorners(tester, fdroid: fdroid, offline: startOffline);

          offlineMode.value = !startOffline;
          await tester.pump();
          expectCorners(tester, fdroid: fdroid, offline: !startOffline);

          // And back, as a user flipping the switch twice.
          offlineMode.value = startOffline;
          await tester.pump();
          expectCorners(tester, fdroid: fdroid, offline: startOffline);
        });
      }
    }

    testWidgets('the update checks switch keeps working while offline', (
      tester,
    ) async {
      offlineMode.value = true;
      await mount(tester);
      final before = shouldWeCheckUpdates.value;
      addTearDown(() => shouldWeCheckUpdates.value = before);

      shouldWeCheckUpdates.value = !before;
      await tester.pump();
      expect(
        bar(tester, l10n.automaticUpdateChecks).borderRadius,
        commonCustomBarRadiusLast,
      );
      final toggle = find.descendant(
        of: barFinder(l10n.automaticUpdateChecks),
        matching: find.byType(Switch),
      );
      expect(tester.widget<Switch>(toggle).value, !before);
    });
  });

  group('accent colour row', () {
    Finder dot(String name) => find.descendant(
      of: barFinder(name),
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle,
      ),
    );

    for (final platform in [TargetPlatform.android, TargetPlatform.linux]) {
      testWidgets('shows the colour in use on ${platform.name}', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        // Only the desktop section reads it, for the downloads folder.
        applicationDirPath = '/tmp/zenify-settings-test';
        try {
          // The dynamic colour, which primaryColorSetting is not.
          useSystemColor.value = true;
          const inUse = Color(0xff00897b);
          expect(primaryColorSetting, isNot(inUse));
          await mount(
            tester,
            wrap: Theme(
              data: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: inUse),
              ),
              child: const SettingsPage(),
            ),
          );

          expect(dot(l10n.accentColor), findsOneWidget);
          final primary = Theme.of(tester.element(find.byType(SettingsPage)))
              .colorScheme
              .primary;
          final decoration =
              tester.widget<Container>(dot(l10n.accentColor)).decoration!
                  as BoxDecoration;
          expect(decoration.color, primary);
          expect(decoration.color, isNot(primaryColorSetting));
          expect(tester.getSize(dot(l10n.accentColor)), const Size(26, 26));
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('other rows have no dot', (tester) async {
      await mount(tester);
      expect(dot(l10n.themeMode), findsNothing);
      expect(dot(l10n.language), findsNothing);
    });
  });

  group('fade between songs row', () {
    final platforms = [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
    ];
    setUp(() => songFadeSeconds.value = 0);
    tearDown(() async {
      songFadeSeconds.value = 0;
      await Hive.box('settings').delete('songFadeSeconds');
    });

    for (final platform in platforms) {
      testWidgets('is there on ${platform.name} and shows its value', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        // Only the desktop section reads it, for the downloads folder.
        applicationDirPath = '/tmp/zenify-settings-test';
        try {
          await mount(tester);
          expect(barFinder(l10n.songFade), findsOneWidget);
          expect(
            bar(tester, l10n.songFade).description,
            l10n.songFadeDescription,
          );
          expect(
            find.descendant(
              of: barFinder(l10n.songFade),
              matching: find.text(l10n.songFadeOff),
            ),
            findsOneWidget,
          );

          songFadeSeconds.value = 6;
          await tester.pump();
          expect(
            find.descendant(
              of: barFinder(l10n.songFade),
              matching: find.text(l10n.songFadeSeconds(6)),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: barFinder(l10n.songFade),
              matching: find.text(l10n.songFadeOff),
            ),
            findsNothing,
          );
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets('opens a dialog of Off and six lengths and saves the choice', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(localizedApp(const SettingsPage()));
        await tester.pump();

        await Scrollable.ensureVisible(
          tester.element(barFinder(l10n.songFade)),
          alignment: 0.5,
        );
        await tester.pump();
        await tester.tap(barFinder(l10n.songFade));
        await tester.pumpAndSettle();

        final dialog = find.byType(AlertDialog);
        expect(dialog, findsOneWidget);
        expect(
          find.descendant(of: dialog, matching: find.text(l10n.songFade)),
          findsOneWidget,
        );
        final options = [
          l10n.songFadeOff,
          for (final seconds in [2, 4, 6, 8, 10, 12])
            l10n.songFadeSeconds(seconds),
        ];
        for (final option in options) {
          expect(
            find.descendant(of: dialog, matching: find.text(option)),
            findsOneWidget,
            reason: option,
          );
        }
        expect(songFadeChoices, [0, 2, 4, 6, 8, 10, 12]);

        await tester.tap(find.text(l10n.songFadeSeconds(8)));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        // The Settings page stays, only the dialog closes.
        expect(find.byType(SettingsPage), findsOneWidget);
        expect(songFadeSeconds.value, 8);
        expect(Hive.box('settings').get('songFadeSeconds'), 8);

        // And back to off.
        await tester.tap(barFinder(l10n.songFade));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(l10n.songFadeOff),
          ),
        );
        await tester.pumpAndSettle();
        expect(songFadeSeconds.value, 0);
        expect(Hive.box('settings').get('songFadeSeconds'), 0);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    group('restoring a backup', () {
      test('brings back the saved length', () async {
        await Hive.box('settings').put('songFadeSeconds', 10);
        reloadSettingsFromStorage();
        expect(songFadeSeconds.value, 10);
      });

      test('turns it off for a library that never had it', () async {
        // A Musify backup has no such key.
        songFadeSeconds.value = 6;
        await Hive.box('settings').delete('songFadeSeconds');
        reloadSettingsFromStorage();
        expect(songFadeSeconds.value, 0);
      });

      test('turns it off for a length that is not a choice', () async {
        for (final stored in [7, -2, 99, 'six', 4.5]) {
          await Hive.box('settings').put('songFadeSeconds', stored);
          reloadSettingsFromStorage();
          expect(songFadeSeconds.value, 0, reason: '$stored');
        }
      });
    });
  });

  group('pickers', () {
    testWidgets('a phone picker is a dialog and applies the chosen option', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final before = audioQualitySetting.value;
      addTearDown(() => audioQualitySetting.value = before);
      try {
        audioQualitySetting.value = 'high';
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(localizedApp(const SettingsPage()));
        await tester.pump();

        // Centred, as the floating title would cover a row at the top edge.
        await Scrollable.ensureVisible(
          tester.element(barFinder(l10n.audioQuality)),
          alignment: 0.5,
        );
        await tester.pump();
        await tester.tap(barFinder(l10n.audioQuality));
        await tester.pumpAndSettle();

        final dialog = find.byType(AlertDialog);
        expect(dialog, findsOneWidget);
        expect(
          find.descendant(of: dialog, matching: find.text(l10n.audioQuality)),
          findsOneWidget,
        );
        for (final option in [
          l10n.audioQualityLow,
          l10n.audioQualityMedium,
          l10n.audioQualityHigh,
        ]) {
          expect(
            find.descendant(of: dialog, matching: find.text(option)),
            findsOneWidget,
          );
        }

        await tester.tap(find.text(l10n.audioQualityLow));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsNothing);
        expect(audioQualitySetting.value, 'low');
        expect(Hive.box('settings').get('audioQuality'), 'low');
        await Hive.box('settings').delete('audioQuality');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
