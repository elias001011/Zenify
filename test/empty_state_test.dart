import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/empty_state.dart';
import 'package:musify/widgets/playlist_page/empty_playlist_state.dart';
import 'package:musify/widgets/spinner.dart';

import 'support/app_harness.dart';

void main() {
  Future<ColorScheme> mount(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(localizedApp(Scaffold(body: child)));
    return Theme.of(tester.element(find.byType(Scaffold))).colorScheme;
  }

  group('EmptyState', () {
    testWidgets('puts the icon over the message in the middle', (tester) async {
      final scheme = await mount(
        tester,
        const EmptyState(
          icon: FluentIcons.folder_24_regular,
          message: 'Nothing here',
        ),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.size, 64);
      expect(icon.color, scheme.onSurface.withAlpha(120));
      final text = tester.widget<Text>(find.text('Nothing here'));
      expect(text.style!.fontSize, 16);
      expect(text.style!.color, scheme.onSurfaceVariant);
      expect(text.textAlign, TextAlign.center);

      final iconRect = tester.getRect(find.byType(Icon));
      final textRect = tester.getRect(find.text('Nothing here'));
      expect(iconRect.bottom + 16, textRect.top);
      final page = tester.getRect(find.byType(Scaffold));
      final shown = iconRect.expandToInclude(textRect);
      expect(shown.center.dx, closeTo(page.center.dx, 0.5));
      expect(shown.center.dy, closeTo(page.center.dy, 0.5));
    });

    testWidgets('is only the message without an icon', (tester) async {
      await mount(tester, const EmptyState(message: 'Nothing here'));

      expect(find.byType(Icon), findsNothing);
      expect(find.text('Nothing here'), findsOneWidget);
    });

    testWidgets('takes the message colour it is given', (tester) async {
      await mount(
        tester,
        const EmptyState(message: 'Nothing here', messageColor: Colors.amber),
      );

      expect(
        tester.widget<Text>(find.text('Nothing here')).style!.color,
        Colors.amber,
      );
    });

    testWidgets('a long message wraps inside the side margins', (tester) async {
      await mount(
        tester,
        EmptyState(message: List.filled(40, 'word').join(' ')),
      );

      final rect = tester.getRect(find.byType(Text));
      expect(rect.left, greaterThanOrEqualTo(32));
      expect(rect.right, lessThanOrEqualTo(400 - 32));
    });

    testWidgets('EmptyPlaylistState fills a scroll view with one', (
      tester,
    ) async {
      await mount(
        tester,
        const CustomScrollView(
          slivers: [EmptyPlaylistState(message: 'No songs')],
        ),
      );

      expect(find.byType(EmptyState), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byType(Icon)).icon,
        FluentIcons.text_bullet_list_24_filled,
      );
      expect(find.text('No songs'), findsOneWidget);
    });
  });

  group('Spinner', () {
    testWidgets('without a size sits in the middle of the room it has', (
      tester,
    ) async {
      final scheme = await mount(
        tester,
        const Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 200, height: 100, child: Spinner()),
        ),
      );

      final rect = tester.getRect(find.byType(CircularProgressIndicator));
      expect(rect.center, const Offset(100, 50));
      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.strokeWidth, isNull);
      expect(indicator.valueColor!.value, scheme.primary);
    });

    testWidgets('with a size is that box, placed by the caller', (
      tester,
    ) async {
      final scheme = await mount(
        tester,
        const Align(
          alignment: Alignment.topLeft,
          child: Spinner(size: 20, strokeWidth: 2),
        ),
      );

      final rect = tester.getRect(find.byType(CircularProgressIndicator));
      expect(rect, const Rect.fromLTWH(0, 0, 20, 20));
      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(indicator.strokeWidth, 2);
      expect(indicator.valueColor!.value, scheme.primary);
    });
  });
}
