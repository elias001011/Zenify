import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/floating_island.dart';

import 'support/app_harness.dart';

const _padding = EdgeInsets.fromLTRB(16, 8, 16, 24);
const _rail = 88.0;

/// A page of controls in a window [width] wide, beside a desktop rail.
Future<Rect> _contentIn(WidgetTester tester, double width) async {
  tester.view
    ..physicalSize = Size(width, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    localizedApp(
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(padding: const EdgeInsets.only(left: _rail)),
          child: Builder(
            builder: (context) => IslandScaffold(
              title: 'Settings',
              globalSearch: false,
              body: ListView(
                padding: readableInset(context, _padding),
                children: const [SizedBox(key: Key('content'), height: 40)],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return tester.getRect(find.byKey(const Key('content')));
}

void main() {
  useAppSettings();

  testWidgets('a wide window centres the content beside the rail', (
    tester,
  ) async {
    final content = await _contentIn(tester, 1600);
    const page = Rect.fromLTRB(_rail, 0, 1600, 900);

    expect(content.width, readableWidth - _padding.horizontal);
    expect(content.center.dx, closeTo(page.center.dx, 0.01));
    expect(content.top, IslandScaffold.inset + _padding.top);
  });

  testWidgets('a narrow window keeps only the padding', (tester) async {
    final content = await _contentIn(tester, 700);

    expect(content.left, _rail + _padding.left);
    expect(content.right, 700 - _padding.right);
  });
}
