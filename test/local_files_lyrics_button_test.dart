import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_service.dart';
import 'package:musify/widgets/now_playing/player_actions.dart';
import 'package:rxdart/rxdart.dart';

class _Handler extends MusifyAudioHandler {
  @override
  Stream<List<Map>> get queueAsMapStream => BehaviorSubject.seeded(const []);
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('musify_local_lyrics');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box);
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  testWidgets('a local file gets no lyrics button, an online song keeps it', (
    tester,
  ) async {
    audioHandler = _Handler();

    for (final id in ['local:0123abcd', 'online-song']) {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PlayerActions(
              metadata: MediaItem(id: id, title: 'Song', extras: {'ytid': id}),
                onPanel: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byTooltip('Lyrics'),
        id.startsWith('local:') ? findsNothing : findsOneWidget,
        reason: 'lyrics button for $id',
      );
    }

    // Let any timer the actions bar started finish before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
