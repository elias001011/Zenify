import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/desktop_window_service.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../support/app_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  const channel = MethodChannel('window_manager');

  useAppSettings(boxes: ['settings']);
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'isMaximized' ||
              call.method == 'isMinimized' ||
              call.method == 'isFullScreen')
            return false;
          return null;
        });
  });
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('musify/window'),
          (call) async => call.method == 'setClientFrame' ? true : null,
        );
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'disabled startup is lazy and rapid toggles keep the last request',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await DesktopWindow.configureClientTitleBar(false);
        expect(calls, isEmpty);
        final enabled = DesktopWindow.configureClientTitleBar(true);
        final disabled = DesktopWindow.configureClientTitleBar(false);
        await Future.wait([enabled, disabled]);
        expect(DesktopWindow.clientTitleBarActive.value, isFalse);
        expect(
          calls
              .where((c) => c.method == 'setTitleBarStyle')
              .last
              .arguments['titleBarStyle'],
          'normal',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'integrated chrome extends the canvas and restores native controls',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      customTitleBar.value = true;
      await DesktopWindow.configureClientTitleBar(true);
      final bodyKey = GlobalKey();
      final safeKey = GlobalKey();
      await tester.pumpWidget(
        localizedApp(
          DesktopTitleBarTheme(
            child: Scaffold(
              body: SizedBox.expand(
                key: bodyKey,
                child: SafeArea(child: SizedBox.expand(key: safeKey)),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DesktopCaptionControls), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(bodyKey)).dy, 0);
      expect(tester.getTopLeft(find.byKey(safeKey)).dy, 44);
      final frame = find.ancestor(
        of: find.byKey(bodyKey),
        matching: find.byType(ClipRRect),
      );
      expect(
        tester.widget<ClipRRect>(frame.first).borderRadius,
        BorderRadius.circular(12),
      );
      final listener =
          (tester.state(find.byType(DesktopTitleBarTheme)) as WindowListener)
            ..onWindowMaximize();
      await tester.pump();
      expect(
        tester.widget<ClipRRect>(frame.first).borderRadius,
        BorderRadius.zero,
      );
      listener.onWindowUnmaximize();
      await tester.pump();
      expect(
        tester.widget<ClipRRect>(frame.first).borderRadius,
        BorderRadius.circular(12),
      );
      expect(
        calls
            .where((call) => call.method == 'setTitleBarStyle')
            .last
            .arguments['titleBarStyle'],
        'hidden',
      );
      final buttons = find.byType(WindowCaptionButton);
      await tester.tap(buttons.first);
      await tester.pump();
      expect(calls.any((call) => call.method == 'minimize'), isTrue);
      await tester.tap(buttons.at(1));
      await tester.pump();
      expect(calls.any((call) => call.method == 'maximize'), isTrue);
      await tester.tap(buttons.last);
      await tester.pump();
      expect(calls.any((call) => call.method == 'close'), isTrue);
      customTitleBar.value = false;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(DesktopCaptionControls), findsNothing);
      expect(
        calls
            .where((call) => call.method == 'setTitleBarStyle')
            .last
            .arguments['titleBarStyle'],
        'normal',
      );
      expect(tester.getTopLeft(find.byKey(safeKey)).dy, 0);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );
  testWidgets('failed frame setup restores native controls and can retry', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var fail = true;
    messenger.setMockMethodCallHandler(const MethodChannel('musify/window'), (
      call,
    ) async {
      if (call.method == 'setClientFrame' && fail)
        throw PlatformException(code: 'frame-failed');
      return true;
    });
    try {
      await DesktopWindow.configureClientTitleBar(false);
      calls.clear();
      await DesktopWindow.configureClientTitleBar(true);
      expect(DesktopWindow.clientTitleBarActive.value, isFalse);
      expect(
        calls
            .where((c) => c.method == 'setTitleBarStyle')
            .map((c) => c.arguments['titleBarStyle']),
        ['hidden', 'normal'],
      );
      fail = false;
      await DesktopWindow.configureClientTitleBar(true);
      expect(DesktopWindow.clientTitleBarActive.value, isTrue);
      await DesktopWindow.configureClientTitleBar(false);
    } finally {
      messenger.setMockMethodCallHandler(
        const MethodChannel('musify/window'),
        null,
      );
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
