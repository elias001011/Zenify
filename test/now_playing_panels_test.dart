import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/now_playing_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/utilities/flutter_bottom_sheet.dart';
import 'package:musify/widgets/now_playing/lyrics_panel.dart';
import 'package:musify/widgets/now_playing/now_playing_artwork.dart';
import 'package:musify/widgets/now_playing/now_playing_controls.dart';
import 'package:musify/widgets/queue_list_view.dart';
import 'package:rxdart/rxdart.dart';

class _Handler extends MusifyAudioHandler {
  final songs = BehaviorSubject<List<Map>>.seeded([
    for (var i = 0; i < 6; i++)
      {
        'ytid': 'song$i',
        'queueEntryId': 'entry$i',
        'title': 'Track $i',
        'artist': 'Artist $i',
      },
  ]);
  int selected = 0;
  int? removed;
  String? reordered;
  int? reorderedTo;

  @override
  Stream<List<Map>> get queueAsMapStream => songs.stream;
  @override
  int get currentQueueIndex => selected;
  @override
  Future<void> skipToSong(int index) async {
    selected = index;
    mediaItem.add(
      MediaItem(
        id: 'song$index',
        title: 'Track $index',
        extras: {'ytid': 'song$index'},
      ),
    );
  }

  @override
  Future<void> removeFromQueue(int index) async {
    removed = index;
    songs.add([...songs.value]..removeAt(index));
  }

  @override
  Future<void> reorderQueueById(String entry, int index) async {
    reordered = entry;
    reorderedTo = index;
    final next = [...songs.value];
    final previous = next.indexWhere((song) => song['queueEntryId'] == entry);
    next.insert(index, next.removeAt(previous));
    songs.add(next);
  }

  @override
  void clearQueue() => songs.add([songs.value[selected]]);
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

  for (final size in [const Size(420, 860), const Size(1280, 800)]) {
    testWidgets(
      'quality badge stays on wide layouts and follows the mobile transition ($size)',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        audioHandler = _Handler();
        showAudioQualityBadge.value = true;
        showPlayerVisualizer.value = false;
        userOfflineSongs.value = [
          {'ytid': 'badge', 'audioBitrateKbps': 192, 'audioCodec': 'opus'},
        ];
        addTearDown(() {
          showAudioQualityBadge.value = false;
          userOfflineSongs.value = [];
        });
        audioHandler.mediaItem.add(
          const MediaItem(
            id: 'badge',
            title: 'Song',
            extras: {'ytid': 'badge'},
          ),
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
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        const badgeText = '192 kbps • Opus';
        final badge = find.text(badgeText);
        double opacity() => tester
            .widgetList<FadeTransition>(
              find.ancestor(of: badge, matching: find.byType(FadeTransition)),
            )
            .fold(1, (value, fade) => value * fade.opacity.value);
        final compact = size.width < 900;
        expect(badge, findsOneWidget);
        expect(opacity(), 1);

        for (final panel in ['Lyrics', 'Queue']) {
          await tester.tap(find.byTooltip(panel));
          await tester.pump();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(opacity(), compact ? lessThan(1) : 1);
          await tester.pump(const Duration(milliseconds: 500));
          expect(opacity(), compact ? 0 : 1);
          await tester.tap(find.byTooltip(panel));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 350));
          expect(opacity(), compact ? greaterThan(0) : 1);
          await tester.pump(const Duration(milliseconds: 150));
          expect(opacity(), 1);
        }
        // Switching directly between panels must never bring the badge back.
        await tester.tap(find.byTooltip('Lyrics'));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byTooltip('Queue'));
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(opacity(), compact ? 0 : 1);

        showAudioQualityBadge.value = false;
        await tester.pump();
        expect(badge, findsNothing);
        showAudioQualityBadge.value = true;
        await tester.pump();
        await tester.pump();
        expect(badge, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 30));
      },
    );
  }

  testWidgets(
    'short desktop windows keep full-size action targets across resizes',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      audioHandler = _Handler();
      audioHandler.mediaItem.add(
        const MediaItem(
          id: 'test',
          title: 'A fairly long song title for the desktop player',
          artist: 'Artist',
          extras: {'ytid': 'test'},
        ),
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      for (final size in [
        const Size(900, 560),
        const Size(1280, 800),
        const Size(900, 560),
      ]) {
        tester.view.physicalSize = size;
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
        await tester.pump();
        if (find.byType(QueueWidget).evaluate().isEmpty) {
          await tester.tap(find.byTooltip('Queue'));
        }
        for (var frame = 0; frame < 20; frame++) {
          await tester.pump(const Duration(milliseconds: 20));
          expect(tester.takeException(), isNull);
        }
        for (final action in [
          'Lyrics',
          'Queue',
          'Volume',
          'Sleep timer',
          'Make available offline',
          'Add to playlist',
          'Liked songs',
        ]) {
          final target = find.byTooltip(action).hitTestable();
          expect(target, findsOneWidget, reason: action);
          final rect = tester.getRect(target);
          expect(rect.width, greaterThanOrEqualTo(44), reason: action);
          expect(rect.height, greaterThanOrEqualTo(44), reason: action);
        }
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('on a phone, lyrics and queue share the artwork area', (
    tester,
  ) async {
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LyricsPanel), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('Lyrics'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(LyricsPanel), findsNothing);

    await tester.tap(find.byTooltip('Queue'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(QueueWidget), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(PlayerControlButtons), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(QueueWidget)).dy,
      greaterThan(tester.getTopLeft(find.byType(NowPlayingArtwork)).dy),
    );
    expect(tester.takeException(), isNull);

    // Lets the lyrics lookup time out before the test ends.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('lyrics opened upright hide sideways and come back', (
    tester,
  ) async {
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(LyricsPanel), findsOneWidget);

    tester.view.physicalSize = const Size(860, 420);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(find.byType(LyricsPanel), findsNothing);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(420, 860);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(LyricsPanel), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });
  Future<void> mountQueue(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    audioHandler = _Handler();
    await audioHandler.skipToSong(0);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const NowPlayingPage(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.tap(find.byTooltip('Queue'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  }

  testWidgets('queue selection, drag, swipe and clear stay inside the player', (
    tester,
  ) async {
    await mountQueue(tester);
    final handler = audioHandler as _Handler;
    await tester.tap(find.text('Track 1'));
    await tester.pump();
    expect(handler.selected, 1);
    expect(find.byType(QueueWidget), findsOneWidget);
    expect(
      tester.widget<QueueTile>(find.byType(QueueTile).at(1)).isCurrentSong,
      isTrue,
    );

    // Flutter reports the final insertion index through onReorderItem.
    tester
        .widget<ReorderableListView>(find.byType(ReorderableListView))
        .onReorderItem!(1, 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(handler.reordered, 'entry1');
    expect(handler.reorderedTo, 2);
    expect(find.byType(QueueWidget), findsOneWidget);

    await tester.drag(find.byType(QueueTile).first, const Offset(-500, 0));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(handler.removed, 0);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(handler.songs.value, hasLength(5));
    await tester.tap(find.byTooltip('Clear'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(handler.songs.value, hasLength(1));
    expect(find.byType(QueueWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('queue survives rotation and closes with the artwork or back', (
    tester,
  ) async {
    await mountQueue(tester);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(QueueWidget), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(QueueWidget), findsOneWidget);
    await tester.tapAt(tester.getRect(find.byType(NowPlayingArtwork)).center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(QueueWidget), findsNothing);
    await tester.pump();
    await tester.tap(find.byTooltip('Queue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(QueueWidget), findsNothing);
    expect(find.byType(NowPlayingPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'queue fits a small phone with large text and rapid panel switches',
    (tester) async {
      await mountQueue(tester, size: const Size(320, 640), scale: 1.3);
      expect(find.byType(QueueWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Lyrics'));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byTooltip('Queue'));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byTooltip('Queue'));
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.byTooltip('Queue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.byType(QueueWidget), findsOneWidget);
      expect(find.byType(LyricsPanel), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    },
  );
  testWidgets('Android keeps the screen awake only while lyrics are visible', (
    tester,
  ) async {
    const channel = MethodChannel('zenify/display');
    final changes = <bool>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      changes.add(call.arguments as bool);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await mountQueue(tester);
    audioHandler.playbackState.add(
      audioHandler.playbackState.value.copyWith(playing: true),
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.tap(find.byTooltip('Lyrics'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(changes, [true]);
    await tester.tap(find.byTooltip('Queue'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(changes, [true, false]);
    tester.view.physicalSize = const Size(844, 390);
    await tester.pump();
    await tester.tap(find.byTooltip('Lyrics'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(changes.last, isTrue);
    closeCurrentBottomSheet();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(changes.last, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    debugDefaultTargetPlatformOverride = null;
  });
}
