import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/database/radio_stations.db.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/library_page.dart';
import 'package:musify/screens/moods_tuning_page.dart';
import 'package:musify/screens/playlist_page.dart';
import 'package:musify/screens/radio_stations_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/moods/moods_preferences.dart';
import 'package:musify/services/playlist_download_service.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/moods_row.dart';
import 'package:musify/widgets/playlist_page/radio_button.dart';
import 'package:musify/widgets/song_bar.dart';

class _Handler extends BaseAudioHandler implements MusifyAudioHandler {
  int playRequests = 0;

  @override
  Future<void> skipToNext({bool playWhenReady = true}) async {}
  @override
  Future<void> skipToPrevious({bool playWhenReady = true}) async {}

  @override
  Future<void> playPlaylistSong({
    Map? playlist,
    required int songIndex,
    bool? shuffle,
    bool keepGoing = false,
  }) async => playRequests++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  late _Handler handler;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('zenify_offline_ui');
    Hive.init(directory.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box);
    }
  });

  setUp(() {
    handler = _Handler();
    audioHandler = handler;
    offlineMode.value = false;
    moodsEnabled.value = true;
    dynamicBackground.value = false;
    floatingEffect.value = FloatingEffect.solid;
    savedZenifyPlaylists.value = ['zenify:daily'];
    userPlaylists.value = [];
    userCustomPlaylists.value = [
      {
        'ytid': 'customId-local',
        'title': 'My local playlist',
        'source': 'user-created',
        'list': <Map>[],
      },
    ];
    userPlaylistFolders.value = [];
    userLikedPlaylists.value = [];
    onlinePlaylists.value = [];
    pinnedPlaylistIds.value = [];
    userOfflineSongs.value = [];
    userLikedSongsList.value = [];
    offlinePlaylistService.offlinePlaylists.value = [];
  });

  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Widget app(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  void size(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> finish(WidgetTester tester) async {
    expect(handler.playRequests, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  }

  for (final hidden in [false, true]) {
    testWidgets(
      'library removes saved Zenify playlists and radios when offline '
      '(hidden tab: $hidden)',
      (tester) async {
        size(tester);
        await tester.pumpWidget(
          app(TickerMode(enabled: !hidden, child: const LibraryPage())),
        );
        await tester.pump(const Duration(milliseconds: 300));
        final l10n = lookupAppLocalizations(const Locale('en'));
        expect(find.text(l10n.radioStations), findsOneWidget);
        expect(find.text(l10n.moodsTuning), findsOneWidget);
        expect(find.byKey(const ValueKey('zenify:daily')), findsOneWidget);

        offlineMode.value = true;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text(l10n.radioStations), findsNothing);
        expect(find.text(l10n.moodsTuning), findsNothing);
        expect(find.byKey(const ValueKey('zenify:daily')), findsNothing);
        expect(find.text('My local playlist'), findsOneWidget);

        offlineMode.value = false;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text(l10n.radioStations), findsOneWidget);
        expect(find.text(l10n.moodsTuning), findsOneWidget);
        expect(find.byKey(const ValueKey('zenify:daily')), findsOneWidget);
        await finish(tester);
      },
    );
  }

  testWidgets('independent radio button follows online/offline changes', (
    tester,
  ) async {
    size(tester);
    await tester.pumpWidget(
      app(StartRadioButton(seeds: () => [], name: 'A playlist')),
    );
    final tooltip = lookupAppLocalizations(const Locale('en')).startRadio;
    expect(find.byTooltip(tooltip), findsOneWidget);
    offlineMode.value = true;
    await tester.pump();
    expect(find.byTooltip(tooltip), findsNothing);
    offlineMode.value = false;
    await tester.pump();
    expect(find.byTooltip(tooltip), findsOneWidget);
    await finish(tester);
  });

  testWidgets('independent moods row follows online/offline changes', (
    tester,
  ) async {
    size(tester);
    await tester.pumpWidget(app(const MoodsRow()));
    final title = lookupAppLocalizations(const Locale('en')).moods;
    expect(find.text(title), findsOneWidget);
    offlineMode.value = true;
    await tester.pump();
    expect(find.text(title), findsNothing);
    offlineMode.value = false;
    await tester.pump();
    expect(find.text(title), findsOneWidget);
    await finish(tester);
  });

  testWidgets(
    'going offline resets the YouTube filter and keeps downloaded songs',
    (tester) async {
      size(tester);
      userOfflineSongs.value = [
        {'ytid': 'downloaded', 'title': 'Downloaded track', 'artist': 'Artist'},
      ];
      await tester.pumpWidget(app(const LibraryPage()));
      await tester.pump(const Duration(milliseconds: 300));
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.widgetWithText(FilterChip, l10n.filterYoutube));
      await tester.pump();
      expect(
        tester
            .widget<FilterChip>(
              find.widgetWithText(FilterChip, l10n.filterYoutube),
            )
            .selected,
        isTrue,
      );

      offlineMode.value = true;
      await tester.pump();
      expect(find.widgetWithText(FilterChip, l10n.filterYoutube), findsNothing);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, l10n.filterAll))
            .selected,
        isTrue,
      );
      expect(find.text('My local playlist'), findsOneWidget);

      await tester.tap(find.byTooltip(l10n.search));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.enterText(find.byType(TextField), 'Downloaded track');
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.widgetWithText(SongBar, 'Downloaded track'), findsOneWidget);
      expect(find.byKey(const ValueKey('zenify:daily')), findsNothing);
      await finish(tester);
    },
  );

  Widget routedApp() => MaterialApp.router(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    routerConfig: NavigationManager.router,
  );

  testWidgets(
    'offline direct routes redirect before mounting discovery pages',
    (tester) async {
      size(tester);
      offlineMode.value = true;
      NavigationManager();
      final router = NavigationManager.router..go('/library');
      await tester.pumpWidget(routedApp());
      await tester.pump(const Duration(milliseconds: 300));
      for (final (path, start) in [
        ('/library/moods-tuning', '/library'),
        ('/library/radioStations', '/library'),
        ('/home/playlist/zenify%3Adaily', '/home'),
      ]) {
        router.go(path);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(router.routeInformationProvider.value.uri.path, start);
        expect(find.byType(MoodsTuningPage), findsNothing);
        expect(find.byType(RadioStationsPage), findsNothing);
        expect(find.byType(PlaylistPage), findsNothing);
      }
      await finish(tester);
    },
  );

  testWidgets('switching offline redirects a radio page already on the stack', (
    tester,
  ) async {
    size(tester);
    // Use the local empty catalog so no remote artwork is requested.
    final catalog = radioStationsDB;
    radioStationsDB = [];
    addTearDown(() => radioStationsDB = catalog);
    offlineMode.value = true;
    NavigationManager();
    final router = NavigationManager.router..go('/library');
    await tester.pumpWidget(routedApp());
    await tester.pump(const Duration(milliseconds: 300));
    offlineMode.value = false;
    await tester.pump();
    unawaited(router.push<void>('/library/radioStations'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(RadioStationsPage), findsOneWidget);

    offlineMode.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(router.routeInformationProvider.value.uri.path, '/library');
    expect(find.byType(RadioStationsPage), findsNothing);
    expect(find.byType(LibraryPage), findsOneWidget);
    expect(router.canPop(), isFalse);
    await finish(tester);
  });

  testWidgets(
    'a Zenify playlist left in the Home tab keeps Home reachable offline',
    (tester) async {
      size(tester);
      await tester.runAsync(
        () => Hive.box('cache').put('moods:playlist:zenify:daily', {
          'ytid': 'zenify:daily',
          'title': 'Daily',
          'list': <Map>[],
          'language': languageSetting.languageCode,
          'tuning': jsonEncode(moodsTuning.value.toStorage()),
          'until': DateTime.now()
              .add(const Duration(days: 1))
              .toIso8601String(),
        }),
      );
      addTearDown(
        () => tester.runAsync(
          () => Hive.box('cache').delete('moods:playlist:zenify:daily'),
        ),
      );
      NavigationManager();
      final router = NavigationManager.router
        ..go('/home/playlist/zenify%3Adaily');
      await tester.pumpWidget(routedApp());
      await tester.pump(const Duration(milliseconds: 300));
      StatefulNavigationShell shell() =>
          tester.widget(find.byType(StatefulNavigationShell));

      shell().goBranch(2);
      await tester.pump(const Duration(milliseconds: 300));
      offlineMode.value = true;
      await tester.pump(const Duration(milliseconds: 300));
      shell().goBranch(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(router.routeInformationProvider.value.uri.path, '/home');
      expect(shell().currentIndex, 0);
      expect(find.byType(PlaylistPage), findsNothing);
      // Home started loading while online; let its retries wind down.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await finish(tester);
    },
  );
}
