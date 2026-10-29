import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/song_selection_bar.dart';
import 'package:musify/widgets/song_selection_controller.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('zenify_selection');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  testWidgets('desktop arrows and wheel reach all batch actions', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    offlineMode.value = false;
    final selection = SongSelectionController()..start({'ytid': 'one'});
    addTearDown(selection.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
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
}
