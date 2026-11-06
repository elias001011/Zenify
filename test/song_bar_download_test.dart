import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/download_manager.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/download_progress_icon.dart';
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
  setUp(() {
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

  testWidgets('a downloading song shows the manager\'s progress on its cover', (
    tester,
  ) async {
    final entry = manager.started(song('a'));
    entry.progress.value = 0.4;
    await tester.pumpWidget(row('a'));

    // The same ring the Downloads tab and the player show, with the same
    // progress, and not a spinner of its own.
    expect(find.byType(DownloadProgressIcon), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(ring(tester).value, 0.4);
    entry.progress.value = 0.8;
    await tester.pump();
    expect(ring(tester).value, 0.8);
  });

  testWidgets('a song that waits in the queue shows the clock', (tester) async {
    manager.queued(song('a'));
    await tester.pumpWidget(row('a'));
    expect(find.byType(DownloadProgressIcon), findsOneWidget);
    expect(find.byIcon(FluentIcons.clock_24_regular), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('it follows a download started elsewhere, and its end', (
    tester,
  ) async {
    await tester.pumpWidget(row('a'));
    expect(find.byType(DownloadProgressIcon), findsNothing);

    final entry = manager.started(song('a'));
    await tester.pump();
    expect(find.byType(DownloadProgressIcon), findsOneWidget);

    manager.finished(entry);
    await tester.pump();
    expect(find.byType(DownloadProgressIcon), findsNothing);
    // The manager's own timers (the end of a run of downloads) run out.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('another song\'s download is not shown on this cover', (
    tester,
  ) async {
    manager.started(song('b'));
    await tester.pumpWidget(row('a'));
    expect(find.byType(DownloadProgressIcon), findsNothing);
  });
}
