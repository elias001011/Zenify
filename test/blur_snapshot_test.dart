import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/blur_snapshot.dart';
import 'package:musify/widgets/floating_island.dart';
import 'package:musify/widgets/floating_surface.dart';

import 'support/app_harness.dart';

const _view = Size(240, 400);
const _surface = Rect.fromLTWH(20, 20, 200, 80);

/// Red on the left half, blue on the right: the slice of the picture under
/// the surface shows where it is taken from.
Widget _halves({Color left = const Color(0xFFFF0000)}) => Row(
  children: [
    Expanded(
      child: ColoredBox(color: left, child: const SizedBox.expand()),
    ),
    const Expanded(
      child: ColoredBox(color: Color(0xFF0000FF), child: SizedBox.expand()),
    ),
  ],
);

Widget _list() => ListView(
  children: [
    for (var i = 0; i < 60; i++)
      SizedBox(
        height: 60,
        child: ColoredBox(
          color: i.isEven ? const Color(0xFFFF0000) : const Color(0xFF0000FF),
        ),
      ),
  ],
);

/// Repaints its whole area on every tick, like a banner that never rests.
class _Banner extends CustomPainter {
  _Banner(this.animation) : super(repaint: animation);
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(
    Offset.zero & size,
    Paint()..color = Color.lerp(Colors.red, Colors.blue, animation.value)!,
  );

  @override
  bool shouldRepaint(_Banner oldDelegate) => false;
}

/// The surface over [content], inside a scope, which is where the app puts
/// every floating surface. [inside] is built inside the captured content.
Widget _app(
  Widget content, {
  Brightness brightness = Brightness.dark,
  Widget? inside,
  Key? capture,
}) => RepaintBoundary(
  key: capture,
  child: MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4),
        brightness: brightness,
      ),
    ),
    home: Scaffold(
      body: BlurSnapshotScope(
        child: Stack(
          fit: StackFit.expand,
          children: [
            BlurSnapshotSource(
              child: Stack(
                fit: StackFit.expand,
                children: [content, if (inside != null) inside],
              ),
            ),
            Positioned.fromRect(
              rect: _surface,
              child: const FloatingSurface(child: SizedBox.expand()),
            ),
          ],
        ),
      ),
    ),
  ),
);

Finder get _surfaces => find.byType(FloatingSurface);

/// The surface that is not inside the captured content.
BlurSnapshot _snapshot(WidgetTester tester) =>
    BlurSnapshot.of(tester.element(_surfaces.last))!;

double _fill(WidgetTester tester, [int surface = -1]) {
  final element = surface < 0 ? _surfaces.last : _surfaces.at(surface);
  return tester
      .widget<Material>(
        find.descendant(of: element, matching: find.byType(Material)),
      )
      .color!
      .a;
}

/// Counts the pictures taken: each one is a new image.
class _Pictures {
  _Pictures(this.snapshot) {
    _last = snapshot.image;
    snapshot.addListener(() {
      if (!identical(snapshot.image, _last)) {
        _last = snapshot.image;
        count++;
      }
    });
  }
  final BlurSnapshot snapshot;
  ui.Image? _last;
  int count = 0;
}

/// Lets the idle delay pass and the (real) capture finish.
Future<void> _untilReady(WidgetTester tester, BlurSnapshot snapshot) async {
  for (var i = 0; i < 200 && !snapshot.ready; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(snapshot.ready, isTrue, reason: 'a picture was taken');
  // The surface rebuilds, then fades the picture in.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pause(WidgetTester tester, Duration time) async {
  await tester.pump();
  await tester.pump(time);
}

/// Lets [time] pass in small steps, with the (real) captures free to finish.
Future<void> _elapse(WidgetTester tester, Duration time) async {
  for (
    var left = time;
    left > Duration.zero;
    left -= const Duration(milliseconds: 100)
  ) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  await tester.pump();
}

class _Pixels {
  _Pixels(this.image, this.bytes);
  final ui.Image image;
  final ByteData bytes;

  /// Red and blue (0 to 1) at [x], [y] of the page.
  (double, double) at(int x, int y) {
    final i = (y * image.width + x) * 4;
    return (bytes.getUint8(i) / 255, bytes.getUint8(i + 2) / 255);
  }
}

Future<_Pixels> _render(WidgetTester tester, GlobalKey capture) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(capture),
  );
  final image = (await tester.runAsync(boundary.toImage))!;
  final bytes = (await tester.runAsync(image.toByteData))!;
  return _Pixels(image, bytes);
}

/// Runs [body] as [platform]; the override is reset before the test ends.
Future<void> _on(TargetPlatform platform, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  useAppSettings(inMemory: true);

  late FloatingEffect startingEffect;
  setUpAll(() => startingEffect = floatingEffect.value);
  setUp(() => floatingEffect.value = FloatingEffect.blurred);
  tearDown(() => floatingEffect.value = startingEffect);

  void phoneView(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = _view;
    addTearDown(tester.view.reset);
  }

  testWidgets('shows the translucent look until the content has rested', (
    tester,
  ) async {
    phoneView(tester);
    await _on(TargetPlatform.android, () async {
      await tester.pumpWidget(_app(_halves()));
      final snapshot = _snapshot(tester);

      expect(snapshot.image, isNull);
      expect(snapshot.ready, isFalse);
      expect(
        _fill(tester),
        closeTo(floatingOpacity(FloatingEffect.translucent, dark: true), 0.005),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(snapshot.image, isNull, reason: 'not before it has settled');

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('takes a picture of the rested content and paints its slice', (
    tester,
  ) async {
    phoneView(tester);
    await _on(TargetPlatform.android, () async {
      final capture = GlobalKey();
      await tester.pumpWidget(_app(_halves(), capture: capture));
      final snapshot = _snapshot(tester);
      await _untilReady(tester, snapshot);

      expect(snapshot.image, isNotNull);
      expect(
        _fill(tester),
        closeTo(floatingOpacity(FloatingEffect.blurred, dark: true), 0.005),
      );
      // The slice comes from behind the surface: red at its left edge, blue
      // at its right, where the content is.
      final pixels = await _render(tester, capture);
      final (leftRed, leftBlue) = pixels.at(30, 60);
      final (rightRed, rightBlue) = pixels.at(210, 60);
      expect(leftRed - leftBlue, greaterThan(0.3));
      expect(rightBlue - rightRed, greaterThan(0.3));

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('the surface inside the captured content never uses it', (
    tester,
  ) async {
    phoneView(tester);
    await _on(TargetPlatform.android, () async {
      await tester.pumpWidget(
        _app(
          _halves(),
          inside: Positioned.fromRect(
            rect: const Rect.fromLTWH(20, 200, 200, 80),
            child: const FloatingSurface(child: SizedBox.expand()),
          ),
        ),
      );
      expect(_surfaces, findsNWidgets(2));
      final inside = tester.element(_surfaces.first);
      expect(BlurSnapshot.of(inside), isNull);
      expect(BlurSnapshot.of(tester.element(_surfaces.last)), isNotNull);

      await _untilReady(tester, _snapshot(tester));
      expect(
        _fill(tester, 1),
        closeTo(floatingOpacity(FloatingEffect.blurred, dark: true), 0.005),
      );
      expect(
        _fill(tester, 0),
        closeTo(floatingOpacity(FloatingEffect.translucent, dark: true), 0.005),
      );

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a scroll falls back to translucent and the end of it takes '
      'a new picture', (tester) async {
    phoneView(tester);
    await _on(TargetPlatform.android, () async {
      await tester.pumpWidget(_app(_list()));
      final snapshot = _snapshot(tester);
      final pictures = _Pictures(snapshot);
      await _untilReady(tester, snapshot);
      final before = pictures.count;

      final gesture = await tester.startGesture(const Offset(120, 300));
      await gesture.moveBy(const Offset(0, -40));
      await gesture.moveBy(const Offset(0, -40));
      await _pause(tester, const Duration(milliseconds: 400));
      expect(snapshot.ready, isFalse);
      expect(
        _fill(tester),
        closeTo(floatingOpacity(FloatingEffect.translucent, dark: true), 0.005),
      );
      // Moving content is never captured.
      for (var i = 0; i < 30; i++) {
        await gesture.moveBy(const Offset(0, -4));
        await _elapse(tester, const Duration(milliseconds: 100));
      }
      expect(snapshot.ready, isFalse);
      expect(pictures.count, before);

      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      await _untilReady(tester, snapshot);
      expect(pictures.count, greaterThan(before));
      expect(
        _fill(tester),
        closeTo(floatingOpacity(FloatingEffect.blurred, dark: true), 0.005),
      );

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a scroll cut off before it ends does not keep the surface '
      'translucent', (tester) async {
    phoneView(tester);
    await _on(TargetPlatform.android, () async {
      await tester.pumpWidget(_app(_list()));
      final snapshot = _snapshot(tester);
      await _untilReady(tester, snapshot);

      final gesture = await tester.startGesture(const Offset(120, 300));
      await gesture.moveBy(const Offset(0, -40));
      await gesture.moveBy(const Offset(0, -40));
      await _pause(tester, const Duration(milliseconds: 100));
      expect(snapshot.ready, isFalse);

      // The list goes (a page popped mid-fling): its scroll never reports
      // that it ended.
      await tester.pumpWidget(_app(_halves()));
      await _untilReady(tester, snapshot);
      await gesture.up();

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a long scroll takes few pictures', (tester) async {
    phoneView(tester);
    await _on(TargetPlatform.android, () async {
      await tester.pumpWidget(_app(_list()));
      final snapshot = _snapshot(tester);
      final pictures = _Pictures(snapshot);
      await _untilReady(tester, snapshot);
      final before = pictures.count;

      for (var i = 0; i < 20; i++) {
        await tester.fling(find.byType(ListView), const Offset(0, -100), 1500);
        await _elapse(tester, const Duration(milliseconds: 100));
      }
      expect(pictures.count, before, reason: 'none while it scrolls');

      await _elapse(tester, const Duration(seconds: 5));
      expect(snapshot.ready, isTrue);
      await _elapse(tester, const Duration(seconds: 5));
      // One once it rests, one more a little later for what loads late.
      expect(pictures.count - before, lessThanOrEqualTo(2));

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a theme change takes a new picture on its own background', (
    tester,
  ) async {
    phoneView(tester);
    await _on(TargetPlatform.android, () async {
      await tester.pumpWidget(_app(_halves()));
      final snapshot = _snapshot(tester);
      final pictures = _Pictures(snapshot);
      await _untilReady(tester, snapshot);
      await tester.pump(const Duration(seconds: 3));
      final before = pictures.count;
      final darkBackground = snapshot.background;

      // The theme eases from one to the other, and the picture is off from
      // the first frame it differs.
      await tester.pumpWidget(_app(_halves(), brightness: Brightness.light));
      await tester.pump(const Duration(milliseconds: 50));
      expect(snapshot.ready, isFalse);
      await _untilReady(tester, snapshot);

      expect(pictures.count, greaterThan(before));
      expect(snapshot.background, isNot(darkBackground));

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets(
    'content that changes at rest is not shown from the old picture',
    (tester) async {
      phoneView(tester);
      await _on(TargetPlatform.android, () async {
        final capture = GlobalKey();
        await tester.pumpWidget(_app(_halves(), capture: capture));
        final snapshot = _snapshot(tester);
        await _untilReady(tester, snapshot);
        await tester.pump(const Duration(seconds: 3));

        await tester.pumpWidget(
          _app(_halves(left: const Color(0xFF00FF00)), capture: capture),
        );
        expect(snapshot.ready, isFalse, reason: 'it no longer matches');
        await _pause(tester, const Duration(milliseconds: 200));
        expect(
          _fill(tester),
          closeTo(
            floatingOpacity(FloatingEffect.translucent, dark: true),
            0.005,
          ),
        );

        await _untilReady(tester, snapshot);
        final pixels = await _render(tester, capture);
        // The new picture is of the new content: green, not red, on the left.
        final (red, _) = pixels.at(30, 60);
        expect(red, lessThan(0.3), reason: 'no red from the old picture left');

        await tester.pumpWidget(const SizedBox());
      });
    },
  );

  testWidgets('a banner that never rests does not take a picture per frame', (
    tester,
  ) async {
    phoneView(tester);
    await _on(TargetPlatform.android, () async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(seconds: 1),
      )..repeat();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(SizedBox.expand(child: CustomPaint(painter: _Banner(controller)))),
      );
      final snapshot = _snapshot(tester);
      final pictures = _Pictures(snapshot);

      for (var i = 0; i < 600; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (i % 50 == 0) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
      }
      // It paints every frame, so it never rests long enough: the surface
      // stays on the translucent look instead of chasing it.
      expect(pictures.count, lessThanOrEqualTo(1));
      expect(snapshot.ready, isFalse);

      // Once it rests, it gets its picture.
      controller.stop();
      await _untilReady(tester, snapshot);

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('an animation in its own layer does not retrigger pictures', (
    tester,
  ) async {
    phoneView(tester);
    await _on(TargetPlatform.android, () async {
      final controller = AnimationController(
        vsync: tester,
        duration: const Duration(seconds: 1),
      )..repeat();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _app(
          SizedBox.expand(
            child: RepaintBoundary(
              child: CustomPaint(painter: _Banner(controller)),
            ),
          ),
        ),
      );
      final snapshot = _snapshot(tester);
      final pictures = _Pictures(snapshot);

      for (var i = 0; i < 600; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (i % 50 == 0) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      // The first one, and the look a little later: no more for ten seconds.
      expect(pictures.count, inInclusiveRange(1, 2));
      controller.stop();

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('a desktop takes no picture and keeps the live blur', (
    tester,
  ) async {
    phoneView(tester);
    await _on(TargetPlatform.linux, () async {
      await tester.pumpWidget(_app(_halves()));
      final snapshot = _snapshot(tester);
      await tester.pump(const Duration(seconds: 5));

      expect(snapshot.image, isNull);
      expect(snapshot.key.currentContext, isNull, reason: 'nothing captured');
      expect(
        find.descendant(of: _surfaces, matching: find.byType(BackdropFilter)),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('leaving blurred drops the picture', (tester) async {
    phoneView(tester);
    await _on(TargetPlatform.android, () async {
      await tester.pumpWidget(_app(_halves()));
      final snapshot = _snapshot(tester);
      await _untilReady(tester, snapshot);

      floatingEffect.value = FloatingEffect.translucent;
      await tester.pump();
      expect(snapshot.image, isNull);
      expect(snapshot.ready, isFalse);
      await tester.pump(const Duration(seconds: 3));
      expect(snapshot.image, isNull, reason: 'it stays off');

      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('takes none while the app is not resumed', (tester) async {
    phoneView(tester);
    final binding = tester.binding;
    await _on(TargetPlatform.android, () async {
      try {
        await tester.pumpWidget(_app(_halves()));
        final snapshot = _snapshot(tester);
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pump(const Duration(seconds: 3));
        expect(snapshot.image, isNull);

        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          binding.handleAppLifecycleStateChanged(state);
        }
        await _untilReady(tester, snapshot);
      } finally {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('the island is blurred from its page, not from itself', (
    tester,
  ) async {
    phoneView(tester);
    await _on(TargetPlatform.android, () async {
      await tester.pumpWidget(
        localizedApp(IslandScaffold(title: 'Page', body: _list())),
      );
      final island = _surfaces;
      expect(island, findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BlurSnapshotSource),
          matching: _surfaces,
        ),
        findsNothing,
        reason: 'the island is not in the picture it is blurred from',
      );
      final snapshot = BlurSnapshot.of(tester.element(island))!;
      await _untilReady(tester, snapshot);
      expect(
        tester
            .widget<Material>(
              find
                  .descendant(of: island, matching: find.byType(Material))
                  .first,
            )
            .color!
            .a,
        closeTo(floatingOpacity(FloatingEffect.blurred, dark: false), 0.005),
      );

      await tester.pumpWidget(const SizedBox());
    });
  });
}
