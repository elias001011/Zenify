import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/download_manager.dart';
import 'package:musify/widgets/download_progress_icon.dart';
import 'package:musify/widgets/now_playing/player_actions.dart';
import 'package:rxdart/rxdart.dart';

class _Handler extends MusifyAudioHandler {
  @override
  Stream<List<Map>> get queueAsMapStream => BehaviorSubject.seeded(const []);
}

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('musify_download_button');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box);
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  setUp(() {
    audioHandler = _Handler();
    DownloadManager.instance
      ..persist = false
      ..reset();
  });

  Widget actions(String id) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: PlayerActions(
        metadata: MediaItem(id: id, title: id, extras: {'ytid': id}),
        onPanel: (_) {},
      ),
    ),
  );

  Finder button() => find.ancestor(
    of: find.byTooltip('Make available offline'),
    matching: find.byType(IconButton),
  );

  testWidgets('the button shows the download of its own song, and only that', (
    tester,
  ) async {
    final manager = DownloadManager.instance;
    await tester.pumpWidget(actions('a'));
    await tester.pump();
    expect(find.byType(DownloadProgressIcon), findsNothing);
    expect(tester.widget<IconButton>(button()).onPressed, isNotNull);

    // Another song downloading changes nothing here.
    final other = manager.started({'ytid': 'b', 'title': 'B'});
    await tester.pump();
    expect(find.byType(DownloadProgressIcon), findsNothing);

    final entry = manager.queued({'ytid': 'a', 'title': 'A'});
    await tester.pump();
    expect(find.byType(DownloadProgressIcon), findsOneWidget);
    // Not pressable meanwhile: it is already on its way.
    expect(tester.widget<IconButton>(button()).onPressed, isNull);

    // The song changes under the same bar, and back: the button follows the
    // manager, not what it showed before.
    await tester.pumpWidget(actions('c'));
    await tester.pump();
    expect(find.byType(DownloadProgressIcon), findsNothing);
    await tester.pumpWidget(actions('a'));
    await tester.pump();
    expect(find.byType(DownloadProgressIcon), findsOneWidget);

    // It fails: the button is back to what it was, not stuck as downloaded.
    manager.failed(entry, 'network');
    await tester.pump();
    expect(find.byType(DownloadProgressIcon), findsNothing);
    expect(tester.widget<IconButton>(button()).onPressed, isNotNull);
    manager.finished(other);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the tooltip says what the button does now', (tester) async {
    await tester.pumpWidget(actions('a'));
    await tester.pump();
    expect(find.byTooltip('Make available offline'), findsOneWidget);
    expect(find.byTooltip('Remove from offline'), findsNothing);

    userOfflineSongs.value = [
      {'ytid': 'a', 'title': 'A'},
    ];
    await tester.pumpWidget(actions('b'));
    await tester.pumpWidget(actions('a'));
    await tester.pump();
    expect(find.byTooltip('Remove from offline'), findsOneWidget);
    expect(find.byTooltip('Make available offline'), findsNothing);

    userOfflineSongs.value = [];
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
