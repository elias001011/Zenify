import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/custom_search_bar.dart';

void main() {
  testWidgets(
    'numpad Enter submits once and Escape leaves search',
    (tester) async {
      final controller = TextEditingController(text: 'Muse');
      final focus = FocusNode();
      final submitted = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomSearchBar(
              controller: controller,
              focusNode: focus,
              labelText: 'Search',
              onSubmitted: submitted.add,
            ),
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      // Flutter's Windows test key map omits Numpad Enter.
      await tester.sendKeyEvent(
        LogicalKeyboardKey.numpadEnter,
        platform: 'linux',
      );
      await tester.pump();
      expect(submitted, ['Muse']);
      expect(focus.hasFocus, isFalse);
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      expect(controller.text, 'Muse');
      expect(submitted, ['Muse']);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      focus.dispose();
      // A keyboard on a tablet or a phone works the same.
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.android,
    }),
  );
}
