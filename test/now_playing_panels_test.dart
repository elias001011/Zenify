import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/now_playing_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/widgets/now_playing/lyrics_panel.dart';
import 'package:musify/widgets/queue_list_view.dart';

class _Handler extends MusifyAudioHandler {
  @override
  Stream<List<Map>> get queueAsMapStream => Stream.value([
    {'ytid': 'test', 'title': 'Song'},
  ]);
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('musify_player_panels');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box);
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  testWidgets('on a phone, lyrics and queue open as sheets', (tester) async {
    tester.view.physicalSize = const Size(420, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    audioHandler = _Handler();
    audioHandler.mediaItem.add(
      const MediaItem(id: 'test', title: 'Song', extras: {'ytid': 'test'}),
    );

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: NowPlayingPage(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Lyrics'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LyricsPanel), findsOneWidget);
    expect(tester.takeException(), isNull);

    Navigator.of(tester.element(find.byType(LyricsPanel))).pop();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byTooltip('Queue'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(QueueWidget), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Lets the lyrics lookup time out before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
}
