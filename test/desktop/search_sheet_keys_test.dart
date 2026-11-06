import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/floating_island.dart';

import '../support/app_harness.dart';

void main() {
  useAppSettings();

  testWidgets(
    'numpad Enter submits once and Escape leaves search',
    (tester) async {
      final controller = TextEditingController(text: 'Muse');
      final focus = FocusNode();
      final submitted = <String>[];
      // The island's page search field, which is what the search page uses.
      await tester.pumpWidget(
        localizedApp(
          IslandScaffold(
            title: 'Search',
            globalSearch: false,
            pageSearch: IslandPageSearch(
              controller: controller,
              focusNode: focus,
              onSubmitted: submitted.add,
            ),
            body: const SizedBox.shrink(),
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
