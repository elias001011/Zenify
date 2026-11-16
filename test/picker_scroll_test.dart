import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/screens/settings_page.dart';
import 'package:musify/services/io_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/custom_bar.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings(inMemory: true);

  final l10n = lookupAppLocalizations(const Locale('en'));

  tearDown(() => useSystemColor.value = true);

  Finder bar(String name) =>
      find.byWidgetPredicate((w) => w is CustomBar && w.tileName == name);

  // Every Settings picker shares one dialog, so each one scrolls the same way
  // when the window is short (a phone turned sideways).
  Map<String, ({String row, String last})> pickersFor(TargetPlatform p) => {
    'theme mode': (row: l10n.themeMode, last: l10n.themeModeDark),
    'audio quality': (row: l10n.audioQuality, last: l10n.audioQualityHigh),
    'fade between songs': (row: l10n.songFade, last: l10n.songFadeSeconds(12)),
    'wave reading': (
      row: l10n.waveReading,
      last: p == TargetPlatform.android
          ? l10n.waveReadingPreciseAndroid
          : l10n.waveReadingPrecise,
    ),
    'floating elements': (
      row: l10n.floatingEffect,
      last: l10n.floatingEffectBlurred,
    ),
  };

  // And when everything fits, nothing scrolls.
  for (final platform in [TargetPlatform.android, TargetPlatform.linux]) {
    for (final entry in pickersFor(platform).entries) {
      testWidgets(
        '${entry.key} does not scroll when it fits on ${platform.name}',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          applicationDirPath = '/tmp/zenify-picker-scroll-test';
          try {
            tester.view.physicalSize = const Size(900, 1400);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await tester.pumpWidget(localizedApp(const SettingsPage()));
            await tester.pump();

            await Scrollable.ensureVisible(
              tester.element(bar(entry.value.row)),
              alignment: 0.5,
            );
            await tester.pump();
            await tester.tap(bar(entry.value.row));
            await tester.pumpAndSettle();

            final dialog = find.byType(AlertDialog);
            expect(dialog, findsOneWidget);
            final scrollables = find.descendant(
              of: dialog,
              matching: find.byType(Scrollable),
            );
            for (final element in scrollables.evaluate()) {
              final position =
                  ((element as StatefulElement).state as ScrollableState)
                      .position;
              expect(position.maxScrollExtent, 0, reason: entry.key);
            }
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.linux]) {
    for (final entry in pickersFor(platform).entries) {
      testWidgets('${entry.key} reaches its last option in a short window '
          'on ${platform.name}', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        applicationDirPath = '/tmp/zenify-picker-scroll-test';
        try {
          tester.view.physicalSize = const Size(844, 300);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(localizedApp(const SettingsPage()));
          await tester.pump();

          await Scrollable.ensureVisible(
            tester.element(bar(entry.value.row)),
            alignment: 0.5,
          );
          await tester.pump();
          await tester.tap(bar(entry.value.row));
          await tester.pumpAndSettle();

          final dialog = find.byType(AlertDialog);
          expect(dialog, findsOneWidget);
          expect(tester.takeException(), isNull);

          // The list scrolls: the last option can always be brought into view.
          final last = find.descendant(
            of: dialog,
            matching: find.text(entry.value.last),
          );
          await tester.scrollUntilVisible(
            last,
            60,
            scrollable: find
                .descendant(of: dialog, matching: find.byType(Scrollable))
                .first,
          );
          expect(last, findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
