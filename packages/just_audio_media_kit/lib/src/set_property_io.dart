library just_audio_media_kit;

import 'package:media_kit/media_kit.dart';

Future<void> setProperty(Player player, String key, dynamic value) async {
  if (player.platform is! NativePlayer) return;
  await (player.platform as NativePlayer).setProperty(key, value);
}

Future<String> getProperty(Player player, String key) async {
  if (player.platform is! NativePlayer) return '';
  return (player.platform as NativePlayer).getProperty(key);
}

Future<void> command(Player player, List<String> args) async {
  if (player.platform is! NativePlayer) return;
  await (player.platform as NativePlayer).command(args);
}
