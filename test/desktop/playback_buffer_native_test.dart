import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_media_kit/mediakit_player.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:media_kit/media_kit.dart';

import '../support/audio_fixture.dart';

void main() {
  final library = Platform.environment['MUSIFY_TEST_LIBMPV'];
  const skip = 'Set MUSIFY_TEST_LIBMPV to run the native backend regression';

  /// A player created the way the app creates it: the engine, then `ready()`.
  Future<MediaKitPlayer> preparedPlayer(String id) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final previousMode = NativePlayer.test;
    NativePlayer.test = true;
    addTearDown(() => NativePlayer.test = previousMode);
    MediaKit.ensureInitialized(libmpv: library);
    final player = MediaKitPlayer(id);
    addTearDown(player.release);
    await player.ready();
    return player;
  }

  Future<double> number(MediaKitPlayer player, String property) async =>
      double.parse(await player.getMpvProperty(property));

  test(
    'mpv caches a song in memory and waits for several seconds after a stall',
    () async {
      final player = await preparedPlayer('buffer-properties');

      expect(await player.getMpvProperty('cache'), 'yes');
      expect(await player.getMpvProperty('cache-on-disk'), 'no');
      expect(await player.getMpvProperty('cache-pause'), 'yes');
      // mpv's own wait is 1 s, which stutters on a slow connection.
      expect(await number(player, 'cache-pause-wait'), 8);
      // Room to read a whole song ahead and keep what was played.
      expect(
        await number(player, 'demuxer-max-bytes'),
        greaterThanOrEqualTo(32 * 1024 * 1024),
      );
      expect(
        await number(player, 'demuxer-max-back-bytes'),
        greaterThanOrEqualTo(32 * 1024 * 1024),
      );
    },
    skip: library == null ? skip : false,
  );

  test(
    'mpv reads a whole streamed song ahead right away',
    () async {
      final wav = silentWav(size: 16000 * 40);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serving = server.listen((request) async {
        final range = RegExp(r'bytes=(\d+)-')
            .firstMatch(request.headers.value('range') ?? '');
        final start = range == null ? 0 : int.parse(range[1]!);
        request.response.headers.contentType = ContentType('audio', 'wav');
        request.response.headers.set('accept-ranges', 'bytes');
        if (range != null) {
          request.response.statusCode = HttpStatus.partialContent;
          request.response.headers.set(
            'content-range',
            'bytes $start-${wav.length - 1}/${wav.length}',
          );
        }
        request.response.contentLength = wav.length - start;
        request.response.add(wav.sublist(start));
        await request.response.close();
      });
      addTearDown(() async {
        await server.close(force: true);
        await serving.cancel();
      });
      final player = await preparedPlayer('buffer-read-ahead');
      await player.setVolume(SetVolumeRequest(volume: 0));
      await player.load(
        LoadRequest(
          audioSourceMessage: ProgressiveAudioSourceMessage(
            id: 'song',
            uri: 'http://127.0.0.1:${server.port}/song.wav',
            headers: const {},
          ),
        ),
      );
      await player.play(PlayRequest());

      // The song lasts 40 s; mpv's default would hold only 1 s ahead.
      var cached = 0.0;
      for (var i = 0; i < 40 && cached < 35; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        cached = await number(player, 'demuxer-cache-duration');
      }
      expect(cached, greaterThanOrEqualTo(35));
    },
    skip: library == null ? skip : false,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
