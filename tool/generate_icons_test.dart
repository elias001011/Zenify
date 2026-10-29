// Draws the Zenify icon (five flat blue bars on black, as the in-app logo) in every size the
// platforms need. Run from the repository root:
//   flutter test tool/generate_icons_test.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/app_logo.dart';

/// The logo's blue: the app's own accent in the dark theme, as the in-app
/// logo shows it.
final _blue = ColorScheme.fromSeed(
  seedColor: const Color(0xff91cef4),
  brightness: Brightness.dark,
).primary;

enum _Style { color, white }

/// Five flat bars in [rect], blue or white, the same in every size.
void _paintWaves(Canvas canvas, Rect rect, _Style style) {
  paintZenifyWaves(
    canvas,
    rect,
    rect.width,
    Paint()..color = style == _Style.color ? _blue : Colors.white,
    bars: 5,
  );
}

/// The launcher icon: black, with rounded corners and a transparent margin
/// unless [square], so it sits among other apps' icons at their size.
void _icon(Canvas canvas, double size, {bool square = false}) {
  final bounds = Offset.zero & Size(size, size);
  final shape = square ? bounds : bounds.deflate(size * 0.09);
  canvas
    ..save()
    ..clipRRect(
      RRect.fromRectAndRadius(
        shape,
        Radius.circular(square ? 0 : shape.width * 0.22),
      ),
    )
    ..drawRect(shape, Paint()..color = Colors.black);
  _paintWaves(
    canvas,
    Rect.fromCenter(
      center: bounds.center,
      width: size * 0.5,
      height: size * 0.5,
    ),
    _Style.color,
  );
  canvas.restore();
}

/// Android adaptive layers: the art inside the 66dp safe zone of 108dp.
void _adaptive(Canvas canvas, double size, _Style style) {
  final center = Offset(size / 2, size / 2);
  _paintWaves(
    canvas,
    Rect.fromCenter(center: center, width: size * 0.44, height: size * 0.44),
    style,
  );
}

/// White silhouette for the notification icon.
void _glyph(Canvas canvas, double size) {
  final center = Offset(size / 2, size / 2);
  _paintWaves(
    canvas,
    Rect.fromCenter(center: center, width: size * 0.92, height: size * 0.92),
    _Style.white,
  );
}

Future<Uint8List> _render(int size, void Function(Canvas, double) paint) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder), size.toDouble());
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Future<void> _write(
  String path,
  int size,
  void Function(Canvas, double) paint,
) async {
  File(path).writeAsBytesSync(await _render(size, paint));
}

/// An .ico holding PNG images, which Windows reads since Vista.
Uint8List _ico(List<(int, Uint8List)> images) {
  final header = BytesBuilder()
    ..add(_u16(0))
    ..add(_u16(1))
    ..add(_u16(images.length));
  final body = BytesBuilder();
  var offset = 6 + 16 * images.length;
  for (final (size, png) in images) {
    header
      ..addByte(size >= 256 ? 0 : size)
      ..addByte(size >= 256 ? 0 : size)
      ..addByte(0)
      ..addByte(0)
      ..add(_u16(1))
      ..add(_u16(32))
      ..add(_u32(png.length))
      ..add(_u32(offset));
    body.add(png);
    offset += png.length;
  }
  return (header..add(body.takeBytes())).takeBytes();
}

List<int> _u16(int v) => [v & 0xff, v >> 8 & 0xff];
List<int> _u32(int v) => [
  v & 0xff,
  v >> 8 & 0xff,
  v >> 16 & 0xff,
  v >> 24 & 0xff,
];

void main() {
  test('generate icons', () async {
    const res = 'android/app/src/main/res';
    const densities = {
      'mdpi': 1.0,
      'hdpi': 1.5,
      'xhdpi': 2.0,
      'xxhdpi': 3.0,
      'xxxhdpi': 4.0,
    };

    for (final MapEntry(key: density, value: scale) in densities.entries) {
      await _write(
        '$res/mipmap-$density/ic_launcher.png',
        (48 * scale).round(),
        _icon,
      );
      await _write(
        '$res/mipmap-$density/ic_launcher_adaptive_fore.png',
        (108 * scale).round(),
        (c, s) => _adaptive(c, s, _Style.color),
      );
      await _write(
        '$res/mipmap-$density/ic_launcher_monochrome.png',
        (108 * scale).round(),
        (c, s) => _adaptive(c, s, _Style.white),
      );
      await _write(
        '$res/drawable-$density/ic_launcher_foreground.png',
        (24 * scale).round(),
        _glyph,
      );
    }

    // The desktop icons must match the Android one byte for byte.
    final launcher = File('$res/mipmap-xxxhdpi/ic_launcher.png')
        .readAsBytesSync();
    File('assets/icons/ic_launcher.png').writeAsBytesSync(launcher);
    File('windows/runner/resources/app_icon.png').writeAsBytesSync(launcher);
    await _write(
      'fastlane/metadata/android/en-US/images/icon.png',
      512,
      (c, s) => _icon(c, s, square: true),
    );

    File('windows/runner/resources/app_icon.ico').writeAsBytesSync(
      _ico([
        for (final size in const [16, 24, 32, 48, 64, 128, 256])
          (size, await _render(size, _icon)),
      ]),
    );
  });
}
