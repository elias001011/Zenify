import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/widgets/song_bar.dart';

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('zenify_offline_art');
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  const ytid = 'dQw4w9WgXcQ';
  // A playlist's own copy, made before the song was downloaded.
  final listed = {
    'ytid': ytid,
    'title': 'Listed song',
    'artist': 'Artist',
    'lowResImage': 'https://i.ytimg.com/vi/$ytid/hqdefault.jpg',
  };

  Future<void> mount(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SongBar(listed, false)),
    ),
  );

  testWidgets('a downloaded song shows its downloaded cover in any list', (
    tester,
  ) async {
    final file = File('${directory.path}/$ytid.jpg')..writeAsBytesSync([0]);
    userOfflineSongs.value = [
      {'ytid': ytid, 'title': 'Listed song', 'artworkPath': file.path},
    ];
    await mount(tester);
    expect(offlineArtworkPath(ytid), file.path);
    expect(
      tester
          .widgetList<Image>(find.byType(Image))
          .map((i) => i.image)
          .any(
            (provider) => provider is FileImage
                ? provider.file.path == file.path
                : provider is ResizeImage &&
                      provider.imageProvider is FileImage &&
                      (provider.imageProvider as FileImage).file.path ==
                          file.path,
          ),
      isTrue,
    );
    userOfflineSongs.value = [];
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a song that is not downloaded keeps its online cover', (
    tester,
  ) async {
    userOfflineSongs.value = [];
    await mount(tester);
    expect(offlineArtworkPath(ytid), isNull);
    expect(
      tester
          .widgetList<Image>(find.byType(Image))
          .map((i) => i.image)
          .any((provider) => provider is FileImage),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
