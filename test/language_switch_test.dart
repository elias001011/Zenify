import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart';
import 'package:musify/screens/settings_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/theme/app_themes.dart';
import 'package:musify/utilities/language_utils.dart';
import 'package:musify/widgets/bottom_sheet_bar.dart';
import 'package:musify/widgets/custom_bar.dart';

import 'support/app_harness.dart';

/// Drives the real app (Musify, its router, the shell and the Settings page)
/// on a phone through the Settings pickers. A picker that closes the wrong
/// route pops the Settings page off its tab, which leaves the router with no
/// page: the screen goes black. Releases up to 0.2.5.1 did this, as their
/// pickers were bottom sheets closed with a pop on the tab's navigator.
void main() {
  useAppSettings(inMemory: true);

  AppLocalizations l10nOf(String code) => lookupAppLocalizations(Locale(code));

  Finder tile(String name) =>
      find.byWidgetPredicate((w) => w is CustomBar && w.tileName == name);

  Future<void> mount(WidgetTester tester, {bool otherTabs = false}) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The previous app, if any, closes every Hive box as it goes away.
    await tester.pumpWidget(const SizedBox());
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name, bytes: Uint8List(0));
    }
    await Hive.box('userNoBackup').put('spotifyImportIntroSeen', true);
    languageSetting = const Locale('en');
    audioHandler = MusifyAudioHandler();
    audioHandler.mediaItem.add(
      const MediaItem(id: 'a', title: 'Song', extras: {'ytid': 'a'}),
    );
    audioHandler.playbackState.add(PlaybackState(playing: true));
    NavigationManager();
    NavigationManager.router.go(
      otherTabs ? NavigationManager.homePath : NavigationManager.settingsPath,
    );
    await tester.pumpWidget(const Musify());
    await tester.pump(const Duration(seconds: 1));
    // The tabs left behind stay alive under the one on screen.
    for (final path in [
      if (otherTabs) ...[
        NavigationManager.libraryPath,
        NavigationManager.searchPath,
        NavigationManager.settingsPath,
      ],
    ]) {
      NavigationManager.router.go(path);
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  void scenario(
    String name,
    Future<void> Function(WidgetTester tester) body, {
    bool otherTabs = false,
  }) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final theme = themeMode;
      final accent = primaryColorSetting;
      final systemColor = useSystemColor.value;
      final quality = audioQualitySetting.value;
      try {
        await mount(tester, otherTabs: otherTabs);
        await body(tester);
      } finally {
        themeMode = theme;
        primaryColorSetting = accent;
        useSystemColor.value = systemColor;
        audioQualitySetting.value = quality;
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 30));
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  /// Opens the picker of [tileName], picks [row], and expects the dialog gone
  /// and the page still there.
  Future<void> pick(
    WidgetTester tester,
    String tileName,
    Finder row, {
    String? reason,
  }) async {
    await tester.tap(tile(tileName));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget, reason: reason);

    await tester.scrollUntilVisible(
      row,
      100,
      scrollable: find.descendant(
        of: dialog,
        matching: find.byType(Scrollable),
      ),
    );
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull, reason: reason);
    expect(find.byType(AlertDialog), findsNothing, reason: reason);
    expect(find.byType(SettingsPage), findsOneWidget, reason: reason);
  }

  Future<void> switchTo(WidgetTester tester, String code) async {
    final page = tester.element(find.byType(SettingsPage));
    final current = Localizations.localeOf(page).languageCode;
    await pick(
      tester,
      l10nOf(current).language,
      find.widgetWithText(BottomSheetBar, getLanguageDisplayName(page, code)),
      reason: '$current -> $code',
    );

    final context = tester.element(find.byType(SettingsPage));
    expect(Localizations.localeOf(context).languageCode, code);
    expect(find.text(l10nOf(code).settings), findsWidgets, reason: code);
    expect(
      Directionality.of(context),
      code == 'he' ? TextDirection.rtl : TextDirection.ltr,
    );
    expect(Hive.box('settings').get('languageCode'), code);
    expect(find.byType(SnackBar), findsOneWidget, reason: code);
  }

  for (final code in appLanguages.where((code) => code != 'en')) {
    scenario('English -> $code keeps the page on screen', (tester) async {
      await switchTo(tester, code);
    });
  }

  scenario('English -> Hebrew -> English, with the other tabs alive', (
    tester,
  ) async {
    await switchTo(tester, 'he');
    await switchTo(tester, 'en');
  }, otherTabs: true);

  group('the other pickers', () {
    final l10n = l10nOf('en');

    scenario('theme mode', (tester) async {
      await pick(
        tester,
        l10n.themeMode,
        find.widgetWithText(BottomSheetBar, l10n.themeModeDark),
      );
      expect(themeMode, ThemeMode.dark);
    });

    scenario('audio quality', (tester) async {
      await pick(
        tester,
        l10n.audioQuality,
        find.widgetWithText(BottomSheetBar, l10n.audioQualityLow),
      );
      expect(audioQualitySetting.value, 'low');
    });

    scenario('accent colour', (tester) async {
      final before = primaryColorSetting;
      await pick(
        tester,
        l10n.accentColor,
        find
            .descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(InkWell),
            )
            .at(3),
      );
      expect(primaryColorSetting, isNot(before));
    });
  });
}
