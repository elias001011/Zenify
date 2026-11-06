import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/utilities/flutter_toast.dart' show toastMessengerKey;

/// Opens the app's Hive boxes for a test file. [inMemory] keeps them out of
/// files, so a write the page starts finishes within the test's fake clock.
void useAppSettings({
  List<String> boxes = const ['settings', 'user', 'userNoBackup', 'cache'],
  bool inMemory = false,
}) {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('zenify_test');
    Hive.init(directory.path);
    for (final name in boxes) {
      await Hive.openBox(name, bytes: inMemory ? Uint8List(0) : null);
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });
}

Widget localizedApp(Widget child) => MaterialApp(
  scaffoldMessengerKey: toastMessengerKey,
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);
