import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/app_notice.dart';

void main() {
  late Directory dir;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('musify_notice');
    Hive.init(dir.path);
    await Hive.openBox('settings');
  });

  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Widget app() => MaterialApp(
    builder: (context, child) => NoticeHost(child: child!),
    home: const Scaffold(
      body: Align(alignment: Alignment.bottomCenter, child: NoticeSlot()),
    ),
  );

  testWidgets('shows in the dock, or floats when the dock is covered', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();

    AppNotices.show(
      const AppNotice('Saved'),
      duration: const Duration(seconds: 3),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NoticeSlot),
        matching: find.text('Saved'),
      ),
      findsOneWidget,
    );

    // A full-screen page covers the dock: the host floats the notice.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NoticeSlot),
        matching: find.text('Saved'),
      ),
      findsNothing,
    );

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('the action runs and closes the notice', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    var undone = false;

    AppNotices.show(
      AppNotice('Removed', actionLabel: 'Undo', onAction: () => undone = true),
      duration: const Duration(seconds: 3),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(undone, isTrue);
    expect(find.text('Removed'), findsNothing);
  });
}
