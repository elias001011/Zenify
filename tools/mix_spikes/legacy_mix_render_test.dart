import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/models/position_data.dart';
import 'package:musify/screens/playlist_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/mix_analysis.dart';
import 'package:musify/services/mix_playlists.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/theme/app_themes.dart';
import 'package:musify/widgets/position_slider.dart';
import 'package:musify/widgets/song_bar.dart';

const _out = '/tmp/claude-1000/-home-elias-repos-Musify-Next/540b1c04-28bd-4c95-8347-e32fc20a9225/scratchpad/renders';

Future<void> _fileFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    loader.addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  }
  await loader.load();
}

Future<void> _font(String family, String asset) async {
  final loader = FontLoader(family)..addFont(rootBundle.load(asset));
  await loader.load();
}

class _Handler extends MusifyAudioHandler {
  final out = ValueNotifier<Duration?>(const Duration(seconds: 172));
  @override
  ValueListenable<Duration?> get mixOutStart => out;
  PositionData data = PositionData(const Duration(seconds: 95), const Duration(seconds: 120), const Duration(seconds: 184));
  @override
  PositionData get currentPositionData => data;
  @override
  Stream<PositionData> get positionDataStream => Stream.value(data);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('zenify_mix_render');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box, bytes: Uint8List(0));
    }
    final material = '${Platform.environment['HOME']}/development/flutter-3.50.0/bin/cache/artifacts/material_fonts';
    await _fileFont('Roboto', ['$material/Roboto-Regular.ttf', '$material/Roboto-Medium.ttf', '$material/Roboto-Bold.ttf']);
    await _fileFont('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
    await _font('paytoneOne', 'assets/fonts/paytone/PaytoneOne-Regular.ttf');
    await _font('packages/fluentui_system_icons/FluentSystemIcons-Regular', 'packages/fluentui_system_icons/fonts/FluentSystemIcons-Regular.ttf');
    await _font('packages/fluentui_system_icons/FluentSystemIcons-Filled', 'packages/fluentui_system_icons/fonts/FluentSystemIcons-Filled.ttf');
  });

  Widget app(Widget child, Brightness brightness) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: getAppTheme(ColorScheme.fromSeed(seedColor: const Color(0xFF7C5CFF), brightness: brightness)),
    locale: const Locale('pt'),
    localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
    supportedLocales: AppLocalizations.supportedLocales,
    home: RepaintBoundary(key: const ValueKey('shot'), child: child),
  );

  Future<void> shot(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
    final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 2)))!;
    final png = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
    File('$_out/$name.png').writeAsBytesSync(png.buffer.asUint8List());
    image.dispose();
  }

  for (final (name, on, brightness) in [('playlist_mix_on', true, Brightness.dark), ('playlist_mix_off', false, Brightness.dark), ('playlist_mix_on_light', true, Brightness.light)]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      offlineMode.value = true;
      mixTransitions.value = true;
      final songs = [
        for (final (i, t) in ['Noite Clara', 'Rua de Cima', 'Vento Sul', 'Fim de Tarde', 'Outra Vez'].indexed)
          {'ytid': 's$i', 'title': t, 'artist': 'Artista $i', 'duration': 200},
      ];
      MixEdge e(double bpm, double beat, int soft, bool tail) => MixEdge(sound: tail ? 198000 : 300, bpm: bpm, beat: beat, beatAt: tail ? 160000 : 400, level: 0.2, soft: soft);
      final cache = Hive.box('cache');
      await cache.put('mix_edge_s0_tail', e(120, 0.8, 500, true).toList());
      await cache.put('mix_edge_s1_head', e(120, 0.8, 0, false).toList());
      await cache.put('mix_edge_s1_tail', e(120, 0.8, 500, true).toList());
      await cache.put('mix_edge_s2_head', e(97, 0.7, 0, false).toList());
      await cache.put('mix_edge_s2_tail', e(97, 0.1, 7000, true).toList());
      await cache.put('mix_edge_s3_head', e(80, 0.05, 0, false).toList());
      userCustomPlaylists.value = [{'ytid': 'p1', 'title': 'Minha playlist', 'source': 'user-created', 'list': songs}];
      mixPlaylists.value = on ? {'p1'} : {};
      audioHandler = _Handler();
      await tester.pumpWidget(app(PlaylistPage(playlistData: userCustomPlaylists.value.single), brightness));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.scrollUntilVisible(find.byType(SongBar).first, 200, scrollable: find.byType(Scrollable).first);
      await tester.pump(const Duration(milliseconds: 400));
      await shot(tester, name);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    });
  }

  for (final (name, at, zone) in [('slider_zone', 95, 172), ('slider_inside_zone', 178, 172), ('slider_no_zone', 95, -1)]) {
    testWidgets(name, (tester) async {
      tester.view.physicalSize = const Size(390, 110);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final handler = _Handler()
        ..data = PositionData(Duration(seconds: at), const Duration(seconds: 184), const Duration(seconds: 184));
      handler.out.value = zone < 0 ? null : Duration(seconds: zone);
      audioHandler = handler;
      await tester.pumpWidget(app(const Scaffold(body: Padding(padding: EdgeInsets.all(24), child: PositionSlider())), Brightness.dark));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await shot(tester, name);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 30));
    });
  }
}
