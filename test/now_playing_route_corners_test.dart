import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/screens/now_playing_page.dart';
import 'package:musify/services/desktop_window_service.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('zenify_corners');
    Hive.init(directory.path);
    await Hive.openBox('settings');
  });
  tearDownAll(
    () => directory.delete(recursive: true).catchError((_) => directory),
  );

  Widget transition(double radius) => WindowCorners(
    radius: radius,
    child: Builder(
      builder: (context) {
        final route = buildNowPlayingRoute() as PageRouteBuilder<void>;
        return route.transitionsBuilder(
          context,
          const AlwaysStoppedAnimation(0.99),
          const AlwaysStoppedAnimation(0),
          const SizedBox.expand(),
        );
      },
    ),
  );

  testWidgets('the rising player clips to a rounded window', (tester) async {
    await tester.pumpWidget(transition(12));
    final clip = tester.widget<ClipRRect>(find.byType(ClipRRect));
    expect(clip.borderRadius, BorderRadius.circular(12));
  });

  testWidgets('a square window adds no clip', (tester) async {
    await tester.pumpWidget(transition(0));
    expect(find.byType(ClipRRect), findsNothing);
  });
}
