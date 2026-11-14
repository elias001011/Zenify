import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/floating_island.dart';
import 'package:musify/widgets/floating_surface.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings();

  testWidgets('the search button keeps to the edge as the title comes in', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final header = GlobalKey();
    await tester.pumpWidget(
      localizedApp(
        IslandScaffold(
          title: 'Liked songs',
          headerTitleKey: header,
          body: ListView(
            padding: const EdgeInsets.only(top: 60),
            children: [
              Text('Liked songs', key: header),
              for (var i = 0; i < 40; i++)
                SizedBox(height: 40, child: Text('$i')),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    Rect island() => tester.getRect(find.byType(FloatingSurface).first);
    Rect search() => tester.getRect(find.byTooltip('Search'));
    final start = island().width;

    await tester.drag(find.byType(ListView), const Offset(0, -200));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }

    // Halfway: the island has grown, and the button is inside its edge.
    expect(island().width, greaterThan(start));
    expect(search().right, lessThanOrEqualTo(island().right));
    expect(search().right, greaterThan(island().right - 16));

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
  });
}
