import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/app_notice.dart';
import 'package:musify/widgets/floating_surface.dart';

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
    home: const Scaffold(body: NoticeDockInset(extent: 100)),
  );

  double noticeBottom(WidgetTester tester) =>
      tester.view.physicalSize.height / tester.view.devicePixelRatio -
      tester.getBottomLeft(find.byType(FloatingSurface)).dy;

  testWidgets('floats above the dock, or near the edge when it is covered', (
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
    // Over the dock's 100 pixels, with a small gap.
    expect(noticeBottom(tester), closeTo(108, 0.5));

    // A full-screen page covers the dock: the notice drops to the edge.
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);
    expect(noticeBottom(tester), closeTo(FloatingSurface.edgeMargin, 0.5));

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('a notice stays long enough to read, whatever was asked', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.pump();

    AppNotices.show(
      const AppNotice('Added to your liked songs'),
      duration: const Duration(seconds: 1),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Added to your liked songs'), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Added to your liked songs'), findsNothing);
  });

  testWidgets('it sits exactly over a dock that does not span the window', (
    tester,
  ) async {
    // The compact desktop dock: 400 pixels wide, from the left margin.
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => NoticeHost(child: child!),
        home: const Scaffold(body: NoticeDockInset(extent: 100, right: 388)),
      ),
    );
    await tester.pump();
    AppNotices.show(
      const AppNotice('Saved'),
      duration: const Duration(seconds: 30),
    );
    await tester.pumpAndSettle();

    final pill = find.byType(FloatingSurface);
    expect(tester.getTopLeft(pill).dx, closeTo(12, 0.5));
    expect(tester.getTopRight(pill).dx, closeTo(412, 0.5));
    AppNotices.dismiss();
    await tester.pumpAndSettle();
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

  testWidgets('dragging the notice down dismisses it early', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump();
    AppNotices.show(
      const AppNotice('Saved'),
      duration: const Duration(seconds: 30),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.text('Saved'), const Offset(0, 10));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsOneWidget);

    await tester.drag(find.text('Saved'), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
    expect(AppNotices.current.value, isNull);

    // The same while the host floats it over a covering page.
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    await tester.pumpAndSettle();
    AppNotices.show(
      const AppNotice('Floating'),
      duration: const Duration(seconds: 30),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.text('Floating'), const Offset(0, 60));
    await tester.pumpAndSettle();
    expect(find.text('Floating'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
