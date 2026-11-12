import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/flip_card.dart';

Widget _card({required bool flipped}) => Directionality(
  textDirection: TextDirection.ltr,
  child: FlipCard(
    frontWidget: const Text('cover'),
    backWidget: const Text('waves'),
    flipped: flipped,
  ),
);

void main() {
  testWidgets('the cover turns to the waves slowly, in 640 ms', (tester) async {
    await tester.pumpWidget(_card(flipped: false));
    await tester.pumpWidget(_card(flipped: true));

    // Halfway is at 320 ms: before it the cover still shows.
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('cover'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.text('waves'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 299));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(milliseconds: 2));
    expect(tester.hasRunningAnimations, isFalse);
  });
}
