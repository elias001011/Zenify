library just_audio_media_kit;

import 'package:media_kit/media_kit.dart';

Future<void> setProperty(Player player, String key, dynamic value) {
  // noop
  return Future.value();
}

Future<String> getProperty(Player player, String key) {
  // noop
  return Future.value('');
}

Future<void> command(Player player, List<String> args) {
  // noop
  return Future.value();
}
