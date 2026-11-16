import 'dart:io';
import 'dart:ui' as ui;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musify/widgets/song_artwork.dart';

void main() {
  testWidgets(
    'a wide cover is decoded by its height, so the square crop is sharp',
    (tester) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('cover');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/wide.png';
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 320, 180),
          Paint()..color = const Color(0xFF336699),
        );
        final image = await recorder.endRecording().toImage(320, 180);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File(path).writeAsBytesSync(png!.buffer.asUint8List());
      });
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 2),
            child: SongArtworkWidget(
              size: 100,
              metadata: MediaItem(id: 'a', title: 'a', artUri: Uri.file(path)),
            ),
          ),
        ),
      );
      final provider = tester.widget<Image>(find.byType(Image)).image;
      expect(provider, isA<ResizeImage>());
      final resize = provider as ResizeImage;
      expect(resize.height, 200);
      expect(resize.width, isNull);
    },
  );
}
