import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/now_playing_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/now_playing/now_playing_artwork.dart';

MediaItem _song(String id) => MediaItem(
  id: id,
  title: 'Song $id',
  artist: 'Artist $id',
  duration: const Duration(minutes: 3),
  extras: {'ytid': 'ytid_$id'},
);

class _Handler extends MusifyAudioHandler {
  @override
  Stream<List<Map>> get queueAsMapStream => Stream.value([
    {'ytid': 'ytid_a', 'title': 'Song a', 'artist': 'Artist a'},
    {'ytid': 'ytid_b', 'title': 'Song b', 'artist': 'Artist b'},
  ]);
  @override
  bool get hasNext => true;
  @override
  bool get hasPrevious => true;

  @override
  Future<void> skipToNext({bool playWhenReady = true}) async {
    mediaItem.add(_song('b'));
  }

  @override
  Future<void> skipToPrevious({bool playWhenReady = true}) async {
    mediaItem.add(_song('a'));
  }
}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('zenify_skip_motion');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box, bytes: Uint8List(0));
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Future<void> pumpPlayer(WidgetTester tester) async {
    audioHandler = _Handler();
    showPlayerVisualizer.value = false;
    audioHandler.mediaItem.add(_song('a'));
    await tester.pumpWidget(_app(const NowPlayingPage()));
    await tester.pump(const Duration(milliseconds: 1600));
  }

  Future<void> disposePlayer(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
    debugDefaultTargetPlatformOverride = null;
  }

  Finder artwork() => find.byType(NowPlayingArtwork);

  /// The horizontal shifts of the covers while one is sliding, in fractions of
  /// the cover's width.
  List<double> coverShifts(WidgetTester tester) => [
    for (final t in tester.widgetList<FractionalTranslation>(
      find.descendant(
        of: artwork(),
        matching: find.byType(FractionalTranslation),
      ),
    ))
      t.translation.dx,
  ];

  testWidgets('a phone slides the cover forward on next and back on previous', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpPlayer(tester);

    await tester.tap(find.byIcon(FluentIcons.next_24_regular));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final forward = coverShifts(tester);
    expect(forward.any((dx) => dx > 0), isTrue);
    expect(forward.any((dx) => dx < 0), isTrue);

    await tester.pump(const Duration(milliseconds: 500));
    expect(
      coverShifts(tester).every((dx) => dx == 0 || dx.abs() < 1e-9),
      isTrue,
    );

    await tester.tap(find.byIcon(FluentIcons.previous_24_regular));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    final back = coverShifts(tester);
    expect(back.any((dx) => dx < 0), isTrue);
    expect(back.any((dx) => dx > 0), isTrue);

    await disposePlayer(tester);
  });

  testWidgets('desktop keeps the cover still on a skip', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await pumpPlayer(tester);

    await tester.tap(find.byIcon(FluentIcons.next_24_regular));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));
    expect(coverShifts(tester), isEmpty);

    await disposePlayer(tester);
  });

  testWidgets('the skip icon leans the way it skips', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await pumpPlayer(tester);

    double leanOf(IconData icon) {
      final transforms = tester.widgetList<Transform>(
        find.ancestor(of: find.byIcon(icon), matching: find.byType(Transform)),
      );
      return transforms
          .map((t) => t.transform.getTranslation().x)
          .reduce((a, b) => a.abs() > b.abs() ? a : b);
    }

    await tester.tap(find.byIcon(FluentIcons.next_24_regular));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(leanOf(FluentIcons.next_24_regular), greaterThan(0));

    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(FluentIcons.previous_24_regular));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(leanOf(FluentIcons.previous_24_regular), lessThan(0));

    await disposePlayer(tester);
  });
}
