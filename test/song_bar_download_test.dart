import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/download_manager.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/download_progress_icon.dart';
import 'package:musify/widgets/overflow_menu_button.dart';
import 'package:musify/widgets/song_bar.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings();

  Map song(String id) => {
    'ytid': id,
    'title': 'Song $id',
    'artist': 'Artist',
    'lowResImage': 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
  };

  Widget row(String id) =>
      localizedApp(Scaffold(body: SongBar(song(id), false)));

  final manager = DownloadManager.instance;
  // A saver that reports [progress] and waits until the test lets it finish.
  final gates = <String, Completer<void>>{};
  final progress = <String, void Function(double)>{};
  Future<void> save(
    Map<String, dynamic> song,
    void Function(double) onProgress,
  ) async {
    final id = song['ytid'] as String;
    progress[id] = onProgress;
    await (gates[id] ??= Completer<void>()).future;
  }

  void finish(String id) => (gates[id] ??= Completer<void>()).complete();

  setUp(() {
    gates.clear();
    progress.clear();
    offlineMode.value = false;
    userOfflineSongs.value = [];
    manager
      ..idleMargin = const Duration(milliseconds: 20)
      ..persist = false
      ..reset()
      ..clearHistory();
  });
  tearDown(() {
    manager
      ..reset()
      ..clearHistory();
  });

  CircularProgressIndicator ring(WidgetTester tester) => tester.widget(
    find.descendant(
      of: find.byType(DownloadProgressIcon),
      matching: find.byType(CircularProgressIndicator),
    ),
  );

  /// Downloads that take every slot, so the next one waits in the queue.
  List<Future<bool>> fillSlots() => [
    for (var i = 0; i < DownloadManager.maxConcurrent; i++)
      manager.download(song('b$i'), save),
  ];

  /// Lets the queue go without the waiting download reaching the network.
  Future<void> drain(WidgetTester tester, List<Future<bool>> running) async {
    unawaited(manager.stopAll());
    for (var i = 0; i < DownloadManager.maxConcurrent; i++) {
      finish('b$i');
    }
    await tester.runAsync(() => Future.wait(running));
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('a song downloaded from its own row shows it on its cover', (
    tester,
  ) async {
    // The test font's wide glyphs would overflow the menu.
    tester.platformDispatcher.textScaleFactorTestValue = 0.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final running = fillSlots();
    await tester.pumpWidget(row('a'));
    await tester.tap(find.byWidgetPredicate((w) => w is OverflowMenuButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Make available offline'));
    await tester.pump();

    // The manager's state, as the Downloads tab shows it: waiting for now.
    expect(find.byType(DownloadProgressIcon), findsOneWidget);
    expect(find.byIcon(FluentIcons.clock_24_regular), findsOneWidget);

    await drain(tester, running);
    expect(find.byType(DownloadProgressIcon), findsNothing);
  });

  testWidgets('a download started elsewhere is not shown on the cover', (
    tester,
  ) async {
    // A playlist's songs, or the player's: the Downloads tab follows them.
    final running = [...fillSlots(), manager.download(song('a'), save)];
    await tester.pumpWidget(row('a'));
    await tester.pump();
    expect(manager.activeFor('a'), isNotNull);
    expect(find.byType(DownloadProgressIcon), findsNothing);

    finish('a');
    await drain(tester, running);
  });

  testWidgets('the ring follows the progress of the download', (tester) async {
    final entry = manager.started(song('a'));
    entry.progress.value = 0.4;
    await tester.pumpWidget(
      localizedApp(Scaffold(body: DownloadProgressIcon(entry))),
    );
    expect(ring(tester).value, 0.4);
    entry.progress.value = 0.8;
    await tester.pump();
    expect(ring(tester).value, 0.8);
  });
}
