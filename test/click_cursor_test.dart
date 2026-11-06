import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/theme/app_themes.dart';
import 'package:musify/widgets/click_region.dart';
import 'package:musify/widgets/dialog_item.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings(inMemory: true);

  Future<void> expectCursor(
    WidgetTester tester,
    TestGesture mouse,
    Finder finder,
    MouseCursor cursor,
  ) async {
    await mouse.moveTo(tester.getCenter(finder.first));
    await tester.pump();
    expect(
      RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
      cursor,
      reason: '$finder',
    );
  }

  testWidgets('what can be tapped shows the hand on desktop, the rest not', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: getAppTheme(
          ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
        ),
        home: Scaffold(
          body: Column(
            children: [
              IconButton(
                key: const Key('icon'),
                onPressed: () {},
                icon: const Icon(Icons.add),
              ),
              IconButton.filled(
                key: const Key('filled-icon'),
                onPressed: () {},
                icon: const Icon(Icons.add),
              ),
              const IconButton(
                key: Key('disabled'),
                onPressed: null,
                icon: Icon(Icons.add),
              ),
              FilledButton(
                key: const Key('filled'),
                onPressed: () {},
                child: const Text('Filled'),
              ),
              TextButton(
                key: const Key('text'),
                onPressed: () {},
                child: const Text('Text'),
              ),
              OutlinedButton(
                key: const Key('outlined'),
                onPressed: () {},
                child: const Text('Outlined'),
              ),
              Switch(key: const Key('switch'), value: false, onChanged: (_) {}),
              ListTile(
                key: const Key('tile'),
                title: const Text('Tile'),
                onTap: () {},
              ),
              DialogItem(
                key: const Key('dialog-item'),
                icon: Icons.add,
                iconColor: Colors.white,
                iconBgColor: Colors.blue,
                label: 'Item',
                onTap: () {},
              ),
              ClickRegion(
                child: GestureDetector(
                  key: const Key('region'),
                  onTap: () {},
                  child: const SizedBox(width: 60, height: 30),
                ),
              ),
              const SizedBox(key: Key('nothing'), width: 60, height: 30),
            ],
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 1,
    );
    await mouse.addPointer(location: const Offset(1, 1));
    addTearDown(mouse.removePointer);

    for (final key in [
      'icon',
      'filled-icon',
      'filled',
      'text',
      'outlined',
      'switch',
      'tile',
      'dialog-item',
      'region',
    ]) {
      await expectCursor(
        tester,
        mouse,
        find.byKey(Key(key)),
        SystemMouseCursors.click,
      );
    }
    await expectCursor(
      tester,
      mouse,
      find.byKey(const Key('disabled')),
      SystemMouseCursors.basic,
    );
    await expectCursor(
      tester,
      mouse,
      find.byKey(const Key('nothing')),
      SystemMouseCursors.basic,
    );
  });
}
