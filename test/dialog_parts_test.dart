import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/extensions/l10n.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/widgets/dialog_parts.dart';

import 'support/app_harness.dart';

void main() {
  late BuildContext page;

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      localizedApp(
        Builder(
          builder: (context) {
            page = context;
            return const Scaffold();
          },
        ),
      ),
    );
  }

  group('DialogCancel', () {
    for (final style in DialogCancelStyle.values) {
      testWidgets('closes the dialog and returns null ($style)', (
        tester,
      ) async {
        await mount(tester);
        var closed = false;
        String? result = 'still open';
        unawaited(
          showDialog<String>(
            context: page,
            builder: (_) => AlertDialog(actions: [DialogCancel(style: style)]),
          ).then((value) {
            closed = true;
            result = value;
          }),
        );
        await tester.pumpAndSettle();
        expect(find.text('Cancel'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(closed, isTrue);
        expect(result, isNull);
        expect(find.byType(AlertDialog), findsNothing);
      });
    }

    testWidgets('has the button of its style', (tester) async {
      await mount(tester);
      unawaited(
        showDialog<void>(
          context: page,
          builder: (_) => const AlertDialog(
            actions: [
              DialogCancel(),
              DialogCancel(style: DialogCancelStyle.mutedText),
              DialogCancel(style: DialogCancelStyle.outlined),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Cancel'), findsNWidgets(2));
      expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsOneWidget);
    });

    testWidgets('runs its own callback instead of closing', (tester) async {
      await mount(tester);
      var pressed = 0;
      unawaited(
        showDialog<void>(
          context: page,
          builder: (_) =>
              AlertDialog(actions: [DialogCancel(onPressed: () => pressed++)]),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(pressed, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
    });
  });

  group('DialogIconHeader', () {
    testWidgets('is a 56 circle in the primary or the secondary colours', (
      tester,
    ) async {
      await mount(tester);
      final scheme = Theme.of(page).colorScheme;
      for (final secondary in [false, true]) {
        await tester.pumpWidget(
          localizedApp(
            Scaffold(
              body: DialogIconHeader(icon: Icons.add, secondary: secondary),
            ),
          ),
        );
        final circle = tester.widget<Container>(find.byType(Container));
        final decoration = circle.decoration! as BoxDecoration;
        expect(decoration.shape, BoxShape.circle);
        expect(
          decoration.color,
          secondary ? scheme.secondaryContainer : scheme.primaryContainer,
        );
        expect(tester.getSize(find.byType(Container)), const Size(56, 56));
        final icon = tester.widget<Icon>(find.byType(Icon));
        expect(icon.color, secondary ? scheme.secondary : scheme.primary);
        expect(icon.size, secondary ? 28 : 32);
      }
    });
  });

  group('showNameDialog', () {
    final submitted = <String>[];

    Future<void> open(WidgetTester tester, {String initialName = ''}) async {
      await mount(tester);
      submitted.clear();
      unawaited(
        showNameDialog(
          page,
          icon: Icons.folder,
          title: 'Edit folder',
          label: 'Folder name',
          initialName: initialName,
          confirmIcon: Icons.save,
          confirmLabel: 'Update',
          onSubmit: (dialogContext, name) {
            expect(dialogContext.mounted, isTrue);
            submitted.add(name);
          },
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('starts with the name, and confirming hands it over trimmed', (
      tester,
    ) async {
      await open(tester, initialName: 'Rock');
      expect(find.text('Edit folder'), findsOneWidget);
      expect(find.text('Rock'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '  Jazz and blues  ');
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(submitted, ['Jazz and blues']);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('confirming without a change hands over the starting name', (
      tester,
    ) async {
      await open(tester, initialName: 'Rock');
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(submitted, ['Rock']);
    });

    testWidgets('an empty name still closes it, and is refused by the caller', (
      tester,
    ) async {
      await open(tester, initialName: 'Rock');
      await tester.enterText(find.byType(TextFormField), '   ');
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(submitted, ['']);
      expect(find.byType(AlertDialog), findsNothing);
      // What the folder dialogs do with it: the manager refuses and says so.
      expect(
        renamePlaylistFolder('folder', submitted.single, page),
        page.l10n!.enterFolderName,
      );
    });

    testWidgets('Cancel closes it without handing anything over', (
      tester,
    ) async {
      await open(tester, initialName: 'Rock');
      await tester.enterText(find.byType(TextFormField), 'Other');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(submitted, isEmpty);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
