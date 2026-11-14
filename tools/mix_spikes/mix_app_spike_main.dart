// Phase 1 check for the Mix: the real audio handler plays three local tones
// with the Mix on, so a recording shows the transitions. Not part of the app.
// Run with HOME pointing at an empty folder, never at a real profile.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:musify/main.dart';
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

  mixTransitions.value = true;
  final files = Platform.environment['SPIKE_SONGS']!.split(',');
  final seconds = int.parse(Platform.environment['SPIKE_SECONDS'] ?? '30');
  final songs = [
    for (final (index, path) in files.indexed)
      {
        'ytid': 'spike_song_$index',
        'title': 'Song $index',
        'artist': 'Spike',
        'duration': seconds,
        'audioPath': path,
      },
  ];
  await audioHandler.addPlaylistToQueue(songs);
  await audioHandler.skipToSong(0);

  final pauseAt = int.tryParse(Platform.environment['SPIKE_PAUSE_AT'] ?? '');
  var paused = false;
  Timer.periodic(const Duration(milliseconds: 500), (_) async {
    final state = audioHandler.playbackState.value;
    log(
      'index=${audioHandler.currentQueueIndex} '
      'song=${audioHandler.mediaItem.value?.title} '
      'pos=${audioHandler.audioPlayer.position.inMilliseconds} '
      'playing=${state.playing} ${state.processingState.name}',
    );
    // A pause of two seconds in the middle of the first transition.
    if (pauseAt != null && !paused && clock.elapsedMilliseconds > pauseAt) {
      paused = true;
      log('PAUSE');
      await audioHandler.pause();
      await Future<void>.delayed(const Duration(seconds: 2));
      log('PLAY');
      await audioHandler.play();
    }
  });
  final total = int.parse(Platform.environment['SPIKE_RUN'] ?? '80');
  await Future<void>.delayed(Duration(seconds: total));
  log('DONE');
  exit(0);
}
