import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/widgets/glow_row.dart';
import 'package:musify/widgets/playlist_cube.dart';
import 'package:musify/widgets/zenify_cover.dart';

const _title = 'Sua playlist do dia com músicas favoritas';
const _image = 'assets/icons/ic_launcher.png';
Map _playlist(int index, {required bool zenify}) => {
  'ytid': 'playlist$index',
  'title': index == 0 ? _title : 'Playlist $index',
  'image': _image,
  if (zenify) ...{'source': 'zenify', 'covers': List.filled(4, _image)},
};

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Center(child: child)),
);

Widget _carousel(bool zenify) => SizedBox(
  height: 190,
  child: GlowCarousel(
    sources: List.filled(6, null),
    onTap: (_) {},
    itemBuilder: (_, index) =>
        PlaylistCube(_playlist(index, zenify: zenify), size: 380),
  ),
);

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('zenify_home_covers');
    Hive.init(directory.path);
    await Hive.openBox('settings');
    dynamicBackground.value = false;
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  for (final textScale in [1.0, 1.8]) {
    testWidgets(
      'mobile cover title keeps its share of the artwork ($textScale)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _app(
            MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 844),
                textScaler: TextScaler.linear(textScale),
              ),
              child: _carousel(true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final cover = tester.getRect(find.byType(ZenifyCover).first);
        final title = tester.getRect(find.text(_title));
        expect(title.height, lessThan(cover.height * 0.28 * textScale));
        expect(title.bottom, lessThan(cover.bottom));
        expect(title.top, greaterThan(cover.top + cover.height * 0.4));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Zenify and recommended covers have one carousel with the same drag and snap',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final offsets = <double>[];
      for (final zenify in [false, true]) {
        await tester.pumpWidget(_app(_carousel(zenify)));
        await tester.pumpAndSettle();
        expect(find.byType(Scrollable), findsOneWidget);
        await tester.drag(find.byType(CarouselView), const Offset(-150, 0));
        await tester.pumpAndSettle();
        offsets.add(
          tester
              .state<ScrollableState>(find.byType(Scrollable))
              .position
              .pixels,
        );
        expect(offsets.last, greaterThan(0));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      expect(offsets[1], closeTo(offsets[0], 0.01));
    },
  );

  testWidgets('desktop cover keeps its existing size and typography', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SizedBox.square(
          dimension: 220,
          child: PlaylistCube(_playlist(0, zenify: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ZenifyCover)), const Size(220, 220));
    expect(tester.widget<Text>(find.text(_title)).style!.fontSize, 22);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
