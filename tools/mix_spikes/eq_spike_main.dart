// Phase 2 proof for the Mix: can the low, mid and high bands of a playing
// mpv be turned down and up at run time, without a click? Not part of the app.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:just_audio_media_kit/mediakit_player.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  JustAudioMediaKit.audioFilters = const [
    '@zmixl:lavfi=[bass=g=0:f=200]',
    '@zmixm:lavfi=[equalizer=f=1000:t=o:w=2:g=0]',
    '@zmixh:lavfi=[treble=g=0:f=4000]',
  ];
  JustAudioMediaKit.pitch = false;
  JustAudioMediaKit.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('eq')))));
  final clock = Stopwatch()..start();
  void log(String message) =>
      // ignore: avoid_print
      print('SPIKE ${clock.elapsedMilliseconds.toString().padLeft(6)} $message');

  final player = AudioPlayer();
  await player.setAudioSource(
    AudioSource.file(Platform.environment['SPIKE_SONG']!),
  );
  unawaited(player.play());
  final mpv = MediaKitPlayer.latest!;
  Future<void> gain(String band, double decibels) async {
    try {
      await mpv.mpvCommand([
        'af-command',
        'zmix$band',
        'gain',
        decibels.toStringAsFixed(1),
      ]);
    } catch (e) {
      log('command failed: $e');
    }
  }

  await Future<void>.delayed(const Duration(seconds: 3));
  log('low down in steps');
  for (var i = 1; i <= 40; i++) {
    await gain('l', -24 * i / 40);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  await Future<void>.delayed(const Duration(seconds: 2));
  log('high down in steps');
  for (var i = 1; i <= 40; i++) {
    await gain('h', -24 * i / 40);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  await Future<void>.delayed(const Duration(seconds: 2));
  log('mid down in steps');
  for (var i = 1; i <= 40; i++) {
    await gain('m', -18 * i / 40);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  await Future<void>.delayed(const Duration(seconds: 2));
  log('all back at once');
  await gain('l', 0);
  await gain('m', 0);
  await gain('h', 0);
  await Future<void>.delayed(const Duration(seconds: 3));
  log('DONE');
  exit(0);
}
