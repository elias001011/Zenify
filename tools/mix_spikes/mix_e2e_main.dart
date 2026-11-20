// End-to-end check of the Mix effects: the real audio handler plays four
// local songs of a playlist with the Mix on; a recording shows the echo, the
// sweep and the Automatic choice. Not part of the app.
// Run with HOME pointing at an empty folder, never at a real profile.
import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart';
import 'package:musify/services/mix_edits.dart';
import 'package:musify/services/mix_playlists.dart';
import 'package:musify/services/mix_transition.dart';
import 'package:musify/services/settings_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final error = await initialisation();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('mix')))));
  final clock = Stopwatch()..start();
  void log(String message) =>
      // ignore: avoid_print
      print('SPIKE ${clock.elapsedMilliseconds.toString().padLeft(6)} $message');
  if (error != null) {
    log('FAILED to start: $error');
    exit(1);
  }
  final folder = Platform.environment['SPIKE_SONGS']!;
  final songs = [
    for (final name in ['a', 'b', 'c', 'd'])
      {
        'ytid': 'spike_$name',
        'title': 'Song $name',
        'artist': 'Spike',
        'duration': 45,
        'audioPath': '$folder/$name.wav',
      },
  ];
  mixTransitions.value = true;
  mixPlaylists.value = {'spike'};
  await mixEdits.set(
    'spike',
    'spike_a',
    'spike_b',
    const MixEdit(
      outStart: Duration(seconds: 32),
      inStart: Duration.zero,
      length: Duration(seconds: 4),
      style: MixStyle.echo,
    ),
  );
  await mixEdits.set(
    'spike',
    'spike_b',
    'spike_c',
    const MixEdit(
      outStart: Duration(seconds: 29),
      inStart: Duration.zero,
      length: Duration(seconds: 8),
      style: MixStyle.sweep,
    ),
  );
  await audioHandler.addPlaylistToQueue(
    songs,
    replace: true,
    playlistId: 'spike',
  );
  await audioHandler.skipToSong(0);
  Timer.periodic(const Duration(milliseconds: 1000), (_) {
    log(
      'song=${audioHandler.mediaItem.value?.title} '
      'pos=${audioHandler.audioPlayer.position.inMilliseconds}',
    );
  });
  final total = int.parse(Platform.environment['SPIKE_RUN'] ?? '130');
  await Future<void>.delayed(Duration(seconds: total));
  log('DONE');
  exit(0);
}
