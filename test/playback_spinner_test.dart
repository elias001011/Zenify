import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/widgets/playback_icon_button.dart';

import 'support/app_harness.dart';
import 'support/wave_test_handler.dart';

void main() {
  useTestSettings();

  testWidgets('a quick load does not flash a spinner, a long one shows it', (
    tester,
  ) async {
    final handler = WaveTestHandler()..ready();
    audioHandler = handler;
    addTearDown(() async {
      await handler.playbackState.close();
      await handler.mediaItem.close();
    });
    await tester.pumpWidget(
      localizedApp(
        const Scaffold(
          body: PlaybackIconButton(
            iconSize: 24,
            iconColor: Colors.white,
            backgroundColor: Colors.transparent,
            buttonSize: 52,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final pause = find.byIcon(FluentIcons.pause_24_filled);
    expect(pause, findsOneWidget);

    // A skip to a song that is offline or already prepared: the optimistic
    // loading state (not playing) is over in a moment.
    handler.playbackState.add(
      PlaybackState(processingState: AudioProcessingState.loading),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(pause, findsOneWidget);
    handler.ready();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(pause, findsOneWidget);

    // A song that really takes time to load gets its spinner.
    handler.playbackState.add(
      PlaybackState(processingState: AudioProcessingState.loading),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    handler.ready();
    // The new state reaches the button, the spinner fades out, then goes.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
