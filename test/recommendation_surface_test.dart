import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/music_list_surface.dart';
import 'package:musify/widgets/recommended_songs_section.dart';
import 'package:musify/widgets/song_bar.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings();

  for (final sliver in [false, true]) {
    testWidgets(
      'music lists have no translucent seams at fractional scroll offsets (sliver: $sliver)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1.25;
        addTearDown(tester.view.reset);
        floatingEffect.value = FloatingEffect.translucent;
        final controller = ScrollController();
        final capture = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: RepaintBoundary(
              key: capture,
              child: Scaffold(
                backgroundColor: const Color(0xFF26364D),
                body: sliver
                    ? CustomScrollView(
                        controller: controller,
                        slivers: [
                          MusicSliverSurface(
                            sliver: SliverList.builder(
                              itemCount: 12,
                              itemBuilder: (context, index) => SongBar(
                                {
                                  'ytid': 'local:$index',
                                  'title': 'Song $index',
                                },
                                true,
                              ),
                            ),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        controller: controller,
                        child: RecommendedSongsSection(
                          title: 'Recommendations',
                          listKeyPrefix: 'seam',
                          showPlayButton: false,
                          songs: [
                            for (var i = 0; i < 12; i++)
                              {'ytid': 'local:$i', 'title': 'Song $i'},
                          ],
                        ),
                      ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final offset in [
          13.3,
          101.7,
          controller.position.maxScrollExtent,
        ]) {
          controller.jumpTo(offset);
          await tester.pumpAndSettle();
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(capture),
          );
          final ratio = tester.view.devicePixelRatio;
          final image = (await tester.runAsync(
            () => boundary.toImage(pixelRatio: ratio),
          ))!;
          final bytes = (await tester.runAsync(image.toByteData))!;
          for (final row in find.byType(SongBar).evaluate().skip(1)) {
            final rect = tester.getRect(find.byWidget(row.widget));
            final y = (rect.top * ratio).round();
            if (y < 40 ||
                y + 2 >= image.height ||
                rect.bottom * ratio > image.height)
              continue;
            // The left padding is empty at each interior row boundary. A single
            // surface must paint exactly the same colour above and below it.
            for (var channel = 0; channel < 4; channel++) {
              int value(int dy) =>
                  bytes.getUint8(((y + dy) * image.width + 5) * 4 + channel);
              expect((value(-1) - value(1)).abs(), lessThanOrEqualTo(1));
            }
          }
          image.dispose();
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
  }
}
