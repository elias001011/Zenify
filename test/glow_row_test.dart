import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/glow_row.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('musify_glow_row');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Widget row() => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 500,
          height: 120,
          child: GlowRow(
            sources: List.filled(10, null),
            itemExtent: 136,
            itemBuilder: (context, index) =>
                SizedBox(width: 120, child: Text('item $index')),
          ),
        ),
      ),
    ),
  );

  testWidgets('desktop arrows follow the scroll position', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(row());
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsOneWidget);
    expect(find.byIcon(FluentIcons.chevron_left_24_regular), findsNothing);

    await tester.tap(find.byIcon(FluentIcons.chevron_right_24_regular));
    await tester.pumpAndSettle();

    expect(find.byIcon(FluentIcons.chevron_left_24_regular), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('phones get no arrows', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(row());
    await tester.pump();

    expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
