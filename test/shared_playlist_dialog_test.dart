import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/utilities/shared_playlist_dialog.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings();

  Future<void> openDialog(WidgetTester tester, List<bool> answers) async {
    await tester.pumpWidget(
      localizedApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(
              await confirmSharedPlaylistImport(
                context,
                title: 'Road trip',
                songCount: 42,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the title and the number of songs', (tester) async {
    final answers = <bool>[];
    await openDialog(tester, answers);

    expect(find.textContaining('"Road trip"'), findsOneWidget);
    expect(find.textContaining('Songs: 42'), findsOneWidget);
    expect(answers, isEmpty);
  });

  testWidgets('Confirm answers true', (tester) async {
    final answers = <bool>[];
    await openDialog(tester, answers);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(answers, [true]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Cancel answers false', (tester) async {
    final answers = <bool>[];
    await openDialog(tester, answers);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(answers, [false]);
  });

  testWidgets('tapping outside the dialog answers false', (tester) async {
    final answers = <bool>[];
    await openDialog(tester, answers);

    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();

    expect(answers, [false]);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
