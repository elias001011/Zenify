import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/services/audio_service.dart';
import 'package:musify/widgets/playback_icon_button.dart';

import 'support/app_harness.dart';

class _Handler extends BaseAudioHandler implements MusifyAudioHandler {
  final pauseAcknowledged = Completer<void>();
  int pauses = 0;
  @override
  Future<void> skipToNext({bool playWhenReady = true}) async {}
  @override
  Future<void> skipToPrevious({bool playWhenReady = true}) async {}
  @override
  Future<void> pause() {
    pauses++;
    playbackState.add(
      PlaybackState(processingState: AudioProcessingState.ready),
    );
    return pauseAcknowledged.future;
  }

  @override
  Future<void> play() async {
    playbackState.add(
      PlaybackState(playing: true, processingState: AudioProcessingState.ready),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final reducedMotion in [false, true]) {
    testWidgets(
      'pause dispatches on tap and the shared icon promptly settles (reduced motion: $reducedMotion)',
      (tester) async {
        final handler = _Handler();
        audioHandler = handler;
        handler.playbackState.add(
          PlaybackState(
            playing: true,
            processingState: AudioProcessingState.ready,
          ),
        );
        await tester.pumpWidget(
          localizedApp(
            MediaQuery(
              data: MediaQueryData(disableAnimations: reducedMotion),
              child: const Scaffold(
                body: Center(
                  child: PlaybackIconButton(
                    iconSize: 36,
                    iconColor: Colors.white,
                    backgroundColor: Colors.transparent,
                    filled: true,
                    buttonSize: 52,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.byTooltip('Pause'));
        expect(handler.pauses, 1);
        expect(handler.pauseAcknowledged.isCompleted, isFalse);
        await tester.pump();
        expect(find.byTooltip('Play'), findsOneWidget);
        await tester.pump(Duration(milliseconds: reducedMotion ? 1 : 125));
        expect(find.byIcon(FluentIcons.pause_24_filled), findsNothing);
        expect(find.byIcon(FluentIcons.play_24_filled), findsOneWidget);
        await tester.tap(find.byTooltip('Play'));
        await tester.pump();
        expect(find.byTooltip('Pause'), findsOneWidget);
        await tester.pump(Duration(milliseconds: reducedMotion ? 1 : 125));
        expect(find.byIcon(FluentIcons.play_24_filled), findsNothing);
        expect(find.byIcon(FluentIcons.pause_24_filled), findsOneWidget);
        handler.pauseAcknowledged.complete();
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
