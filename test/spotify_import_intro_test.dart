import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/import_spotify_playlist_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/router_service.dart';
import 'package:musify/widgets/spotify_import_intro.dart';

class _Handler extends BaseAudioHandler implements MusifyAudioHandler {
  @override
  Future<void> skipToNext({bool playWhenReady = true}) async {}

  @override
  Future<void> skipToPrevious({bool playWhenReady = true}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    audioHandler = _Handler();
    final directory = await Directory.systemTemp.createTemp('zenify_intro');
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Not awaited: under a test clock a write never settles, and the box
    // answers from memory at once.
    unawaited(Hive.box('userNoBackup').delete('spotifyImportIntroSeen'));
    NavigationManager();
    NavigationManager.router.go('/library');
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
    await tester.pump(const Duration(milliseconds: 300));
    expect(spotifyImportIntroSeen, isFalse);
    unawaited(showSpotifyImportIntro(NavigationManager().context));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Bring your Spotify playlists'), findsOneWidget);
  }

  testWidgets('dismissing ends it for good', (tester) async {
    await open(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Dismiss'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Bring your Spotify playlists'), findsNothing);
    expect(spotifyImportIntroSeen, isTrue);
    expect(find.byType(ImportSpotifyPlaylistPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('importing goes to the import and ends it for good', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(spotifyImportIntroSeen, isTrue);
    expect(find.byType(ImportSpotifyPlaylistPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}
