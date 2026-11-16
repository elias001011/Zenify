import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/keyboard_shortcuts_manager.dart';

import '../support/app_harness.dart';

class _Handler extends MusifyAudioHandler {
  var plays = 0;

  @override
  Future<void> play() async => plays++;
}

void main() {
  useAppSettings();

  late _Handler handler;
  setUp(() => audioHandler = handler = _Handler());

  Future<void> pumpApp(WidgetTester tester, Widget body) => tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => GlobalShortcuts(child: child!),
      home: Scaffold(body: body),
    ),
  );

  testWidgets('Space on a focused switch flips it, not the playback', (
    tester,
  ) async {
    var on = false;
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await pumpApp(
      tester,
      StatefulBuilder(
        builder: (context, setState) => Switch(
          focusNode: focus,
          value: on,
          onChanged: (value) => setState(() => on = value),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(on, isTrue);
    expect(handler.plays, 0);
  });

  testWidgets('Space with no control focused still plays', (tester) async {
    await pumpApp(tester, const Text('Library'));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();

    expect(handler.plays, 1);
  });
}
