import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/floating_surface.dart';

import 'support/app_harness.dart';

const _surface = Rect.fromLTWH(20, 20, 200, 80);

/// The surface on a plain page, so every difference inside it is its own.
Widget _page(Brightness brightness, Key capture) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF6750A4),
    brightness: brightness,
  );
  return RepaintBoundary(
    key: capture,
    child: MaterialApp(
      theme: ThemeData(colorScheme: scheme),
      home: Scaffold(
        backgroundColor: scheme.surface,
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.only(left: _surface.left, top: _surface.top),
            child: SizedBox.fromSize(
              size: _surface.size,
              child: const FloatingSurface(child: SizedBox.expand()),
            ),
          ),
        ),
      ),
    ),
  );
}

Finder _inSurface(Finder matching) =>
    find.descendant(of: find.byType(FloatingSurface), matching: matching);

/// Runs [body] as [platform]; the override is reset before the test ends.
Future<void> _on(TargetPlatform platform, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

/// Red channel (0 to 1) of the page where it is painted, to compare spots.
class _Pixels {
  _Pixels(this._image, this._bytes);
  final ui.Image _image;
  final ByteData _bytes;

  /// [x] and [y] are relative to the surface's top-left corner.
  double at(num x, num y) {
    final px = (_surface.left + x).floor();
    final py = (_surface.top + y).floor();
    return _bytes.getUint8((py * _image.width + px) * 4) / 255;
  }
}

void main() {
  useAppSettings(inMemory: true);

  late FloatingEffect startingEffect;
  setUpAll(() => startingEffect = floatingEffect.value);
  tearDown(() => floatingEffect.value = startingEffect);

  Future<_Pixels> paint(
    WidgetTester tester,
    FloatingEffect effect,
    Brightness brightness, {
    TargetPlatform platform = TargetPlatform.linux,
  }) async {
    floatingEffect.value = effect;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(240, 120);
    addTearDown(tester.view.reset);
    final capture = GlobalKey();
    late _Pixels pixels;
    await _on(platform, () async {
      await tester.pumpWidget(_page(brightness, capture));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(capture),
      );
      final image = (await tester.runAsync(boundary.toImage))!;
      final bytes = (await tester.runAsync(image.toByteData))!;
      pixels = _Pixels(image, bytes);
    });
    return pixels;
  }

  testWidgets('on a desktop only the blurred surface reads what is behind it', (
    tester,
  ) async {
    await _on(TargetPlatform.linux, () async {
      for (final effect in FloatingEffect.values) {
        floatingEffect.value = effect;
        await tester.pumpWidget(_page(Brightness.dark, GlobalKey()));
        expect(
          _inSurface(find.byType(BackdropFilter)),
          effect == FloatingEffect.blurred ? findsOneWidget : findsNothing,
          reason: effect.name,
        );
      }
    });
  });

  testWidgets('on a phone no surface reads what is behind it', (tester) async {
    await _on(TargetPlatform.android, () async {
      for (final effect in FloatingEffect.values) {
        floatingEffect.value = effect;
        await tester.pumpWidget(_page(Brightness.dark, GlobalKey()));
        expect(
          _inSurface(find.byType(BackdropFilter)),
          findsNothing,
          reason: effect.name,
        );
      }
    });
  });

  testWidgets('only the solid surface casts a shadow', (tester) async {
    for (final effect in FloatingEffect.values) {
      floatingEffect.value = effect;
      await tester.pumpWidget(_page(Brightness.dark, GlobalKey()));
      final shadowed = _inSurface(
        find.byWidgetPredicate(
          (widget) =>
              widget is DecoratedBox &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).boxShadow?.isNotEmpty ==
                  true,
        ),
      );
      expect(
        shadowed,
        effect == FloatingEffect.solid ? findsOneWidget : findsNothing,
        reason: effect.name,
      );
    }
  });

  test('each effect keeps its opacity', () {
    expect(floatingOpacity(FloatingEffect.solid, dark: true), 1);
    expect(floatingOpacity(FloatingEffect.solid, dark: false), 1);
    expect(floatingOpacity(FloatingEffect.translucent, dark: true), 0.9);
    expect(floatingOpacity(FloatingEffect.translucent, dark: false), 0.92);
    expect(floatingOpacity(FloatingEffect.blurred, dark: true), 0.5);
    expect(floatingOpacity(FloatingEffect.blurred, dark: false), 0.6);
  });

  testWidgets('the fill is painted at the opacity of its effect', (
    tester,
  ) async {
    await _on(TargetPlatform.linux, () async {
      for (final brightness in Brightness.values) {
        for (final effect in FloatingEffect.values) {
          floatingEffect.value = effect;
          await tester.pumpWidget(_page(brightness, GlobalKey()));
          final fill = tester.widget<Material>(
            _inSurface(find.byType(Material)),
          );
          expect(
            fill.color!.a,
            closeTo(
              floatingOpacity(effect, dark: brightness == Brightness.dark),
              0.005,
            ),
            reason: '${effect.name} ${brightness.name}',
          );
        }
      }
    });
  });

  testWidgets('on a phone blurred without a picture is as opaque as '
      'translucent', (tester) async {
    await _on(TargetPlatform.android, () async {
      for (final brightness in Brightness.values) {
        floatingEffect.value = FloatingEffect.blurred;
        await tester.pumpWidget(_page(brightness, GlobalKey()));
        final fill = tester.widget<Material>(_inSurface(find.byType(Material)));
        expect(
          fill.color!.a,
          closeTo(
            floatingOpacity(
              FloatingEffect.translucent,
              dark: brightness == Brightness.dark,
            ),
            0.005,
          ),
          reason: brightness.name,
        );
      }
    });
  });

  group('the glass catches light', () {
    // The top fades in a white sheen: inside the surface, near the top, it is
    // lighter than near the bottom.
    double sheen(_Pixels p) => p.at(100, 8) - p.at(100, 72);

    // The rim is brightest where the top-left corner curves, lighter than the
    // fill just inside it.
    double rim(_Pixels p) => p.at(8.5, 8.5) - p.at(12.7, 12.7);

    testWidgets('the translucent surface fades a sheen in from the top', (
      tester,
    ) async {
      final pixels = await paint(
        tester,
        FloatingEffect.translucent,
        Brightness.dark,
      );
      expect(sheen(pixels), greaterThan(0.03));
    });

    testWidgets('the translucent surface has a rim brightest at the top-left', (
      tester,
    ) async {
      final pixels = await paint(
        tester,
        FloatingEffect.translucent,
        Brightness.dark,
      );
      expect(rim(pixels), greaterThan(0.15));
    });

    for (final effect in [FloatingEffect.solid, FloatingEffect.blurred]) {
      testWidgets('the ${effect.name} surface has neither', (tester) async {
        final pixels = await paint(tester, effect, Brightness.dark);
        expect(sheen(pixels).abs(), lessThan(0.005));
        expect(rim(pixels), lessThan(0.1));
      });
    }

    testWidgets('on a phone the blurred surface has both, like translucent', (
      tester,
    ) async {
      final pixels = await paint(
        tester,
        FloatingEffect.blurred,
        Brightness.dark,
        platform: TargetPlatform.android,
      );
      expect(sheen(pixels), greaterThan(0.03));
      expect(rim(pixels), greaterThan(0.15));
    });
  });
}
