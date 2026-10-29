import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_service.dart';
import 'package:musify/widgets/mini_player.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('musify_mini_player');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box);
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Widget app(Key key) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: MiniPlayer(key: key)),
  );

  testWidgets('a mini player built later still shows the song', (
    tester,
  ) async {
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
}
