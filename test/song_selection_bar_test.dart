import 'dart:async';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/download_manager.dart';
import 'package:musify/services/io_service.dart';
import 'package:musify/services/local_files_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/confirmation_dialog.dart';
import 'package:musify/widgets/song_selection_bar.dart';
import 'package:musify/widgets/song_selection_controller.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings();

  testWidgets('desktop arrows and wheel reach all batch actions', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    offlineMode.value = false;
    final selection = SongSelectionController()..start({'ytid': 'one'});
    addTearDown(selection.dispose);
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: Center(
            child: SizedBox(
              width: 480,
              child: SongSelectionBar(
                controller: selection,
                visibleSongs: () => [
                  {'ytid': 'one'},
                ],
                onMoveSelected: (_) async {},
                onRemoveSelected: (_) async {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final next = find.widgetWithIcon(
      IconButton,
      FluentIcons.chevron_right_24_regular,
    );
    final previous = find.widgetWithIcon(
      IconButton,
      FluentIcons.chevron_left_24_regular,
    );
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(tester.widget<IconButton>(previous).onPressed, isNull);
    expect(tester.widget<IconButton>(next).onPressed, isNotNull);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(0));
    expect(tester.widget<IconButton>(previous).onPressed, isNotNull);
    for (var i = 0; i < 10 && scroll.position.extentAfter > 0; i++) {
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
    expect(scroll.position.extentAfter, 0);
    expect(
      find
          .widgetWithIcon(TextButton, FluentIcons.delete_24_regular)
          .hitTestable(),
      findsOneWidget,
    );
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.byType(SingleChildScrollView)),
        scrollDelta: const Offset(0, -150),
      ),
    );
    await tester.pumpAndSettle();
    expect(scroll.position.extentAfter, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.linux]) {
    testWidgets(
      'compact selection scrolls by drag without arrows ($platform)',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        offlineMode.value = false;
        final selection = SongSelectionController()..start({'ytid': 'one'});
        await tester.pumpWidget(
          localizedApp(
            Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: SongSelectionBar(
                  controller: selection,
                  visibleSongs: () => [
                    {'ytid': 'one'},
                  ],
                  onRemoveSelected: (_) async {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byIcon(FluentIcons.chevron_left_24_regular), findsNothing);
        expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsNothing);
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(-1200, 0),
        );
        await tester.pumpAndSettle();
        expect(
          find
              .widgetWithIcon(TextButton, FluentIcons.delete_24_regular)
              .hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        selection.dispose();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  group('a tablet', () {
    Future<ScrollableState> mount(WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      offlineMode.value = false;
      final selection = SongSelectionController()..start({'ytid': 'one'});
      addTearDown(selection.dispose);
      await tester.pumpWidget(
        localizedApp(
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 480,
                child: SongSelectionBar(
                  controller: selection,
                  visibleSongs: () => [
                    {'ytid': 'one'},
                  ],
                  onMoveSelected: (_) async {},
                  onRemoveSelected: (_) async {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.state<ScrollableState>(find.byType(Scrollable));
    }

    testWidgets('gets the arrows once a mouse is connected, not before', (
      tester,
    ) async {
      await mount(tester);
      expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsNothing);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsOneWidget);
      expect(find.byIcon(FluentIcons.chevron_left_24_regular), findsOneWidget);

      await mouse.removePointer();
      await tester.pumpAndSettle();
      expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsNothing);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('scrolls with the wheel of a mouse', (tester) async {
      final scroll = await mount(tester);
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(SingleChildScrollView)),
          scrollDelta: const Offset(0, 150),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  });

  testWidgets('toggling offline mode updates the available batch actions', (
    tester,
  ) async {
    offlineMode.value = false;
    addTearDown(() => offlineMode.value = false);
    final selection = SongSelectionController()..start({'ytid': 'one'});
    addTearDown(selection.dispose);
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: SongSelectionBar(
            controller: selection,
            visibleSongs: () => [
              {'ytid': 'one'},
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(FluentIcons.heart_24_regular), findsOneWidget);

    offlineMode.value = true;
    await tester.pumpAndSettle();
    expect(find.byIcon(FluentIcons.heart_24_regular), findsNothing);
  });

  testWidgets('offline actions require a common action and update live', (
    tester,
  ) async {
    const first = {'ytid': 'aaaaaaaaaaa'};
    const second = {'ytid': 'bbbbbbbbbbb'};
    final local = {'ytid': '${localSongPrefix}one'};
    final selection = SongSelectionController()
      ..start(first)
      ..toggle(second);
    final downloads = DownloadManager.instance..persist = false;
    addTearDown(() {
      selection.dispose();
      downloads
        ..reset()
        ..persist = true;
      offlineMode.value = false;
      userOfflineSongs.value = [];
    });
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: SongSelectionBar(
            controller: selection,
            visibleSongs: () => [first, second, local],
          ),
        ),
      ),
    );
    final makeOffline = find.text('Make available offline');
    final cancel = find.text('Cancel download');
    final remove = find.text('Remove from offline');
    expect(makeOffline, findsOneWidget);

    selection.toggle(local);
    await tester.pump();
    expect(makeOffline, findsNothing);
    selection.toggle(local);

    userOfflineSongs.value = [first];
    await tester.pump();
    expect(makeOffline, findsNothing);
    expect(remove, findsNothing);

    userOfflineSongs.value = [first, second];
    await tester.pump();
    expect(remove, findsOneWidget);
    offlineMode.value = true;
    await tester.pump();
    expect(remove, findsOneWidget);

    await tester.ensureVisible(remove);
    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.byType(ConfirmationDialog), findsOneWidget);
    expect(userOfflineSongs.value, [first, second]);
    final root = Directory.systemTemp.createTempSync('zenify_batch_remove');
    addTearDown(() => root.deleteSync(recursive: true));
    applicationDirPath = downloadsDirPath = root.path;
    Directory('${root.path}/${FilePaths.tracksDir}').createSync();
    final files = [
      for (final song in [first, second])
        File(FilePaths.getAudioPath(song['ytid']!))..writeAsStringSync('audio'),
    ];
    await tester.runAsync(() async {
      final removed = Completer<void>();
      void onOfflineChanged() {
        if (userOfflineSongs.value.isEmpty) removed.complete();
      }

      userOfflineSongs.addListener(onOfflineChanged);
      try {
        await tester.tap(
          find.descendant(
            of: find.byType(ConfirmationDialog),
            matching: remove,
          ),
        );
        await removed.future;
      } finally {
        userOfflineSongs.removeListener(onOfflineChanged);
      }
    });
    await tester.pump();
    expect(files.every((file) => !file.existsSync()), isTrue);

    offlineMode.value = false;
    selection
      ..start(first)
      ..toggle(second);
    final release = Completer<void>();
    Future<void> save(Map song, void Function(double) progress) async {
      await release.future;
      progress(0.5);
    }

    final firstDownload = downloads.download(first, save);
    await tester.pump();
    expect(makeOffline, findsNothing);
    expect(cancel, findsNothing);
    final secondDownload = downloads.download(second, save);
    await tester.pump();
    expect(cancel, findsOneWidget);

    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    release.complete();
    expect(await Future.wait([firstDownload, secondDownload]), [false, false]);
    await tester.pump(const Duration(seconds: 4));
    expect(downloads.active, isEmpty);
  });
}
