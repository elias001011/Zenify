import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/bottom_sheet_bar.dart';

import 'support/app_harness.dart';

void main() {
  testWidgets('a chosen bar tells screen readers it is selected', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      localizedApp(
        Scaffold(
          body: Column(
            children: [
              BottomSheetBar('Chosen', () => taps++, true),
              BottomSheetBar('Other', () => taps++, false),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getSemantics(find.text('Chosen')),
      isSemantics(label: 'Chosen', isSelected: true, hasTapAction: true),
    );
    expect(
      tester.getSemantics(find.text('Other')),
      isSemantics(label: 'Other', isSelected: false, hasTapAction: true),
    );

    await tester.tap(find.text('Other'));
    expect(taps, 1);
    semantics.dispose();
  });
}
