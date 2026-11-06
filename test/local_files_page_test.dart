import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/local_files_page.dart';
import 'package:musify/services/audio_service.dart';
import 'package:musify/services/local_files_service.dart';

import 'support/app_harness.dart';

class _Handler extends MusifyAudioHandler {
  Map? playlist;
  int? index;

  @override
  Future<void> playPlaylistSong({
    Map<dynamic, dynamic>? playlist,
    required int songIndex,
    bool? shuffle,
    bool keepGoing = false,
  }) async {
    this.playlist = playlist;
    index = songIndex;
  }
}

void main() {
  useAppSettings();

  testWidgets('the island search filters the files and keeps the whole list '
      'playing from the song picked', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handler = _Handler();
    audioHandler = handler;
    localFiles.value = [
      {'ytid': 'local:a', 'title': 'Morning', 'artist': ''},
      {'ytid': 'local:b', 'title': 'The Sea', 'artist': ''},
      {'ytid': 'local:c', 'title': 'Evening', 'artist': 'Sea Band'},
    ];
    addTearDown(() => localFiles.value = []);

    await tester.pumpWidget(localizedApp(const LocalFilesPage()));
    await tester.pumpAndSettle();
    expect(find.text('Morning'), findsOneWidget);
    expect(find.text('The Sea'), findsOneWidget);
    expect(find.text('Evening'), findsOneWidget);

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), ' sea ');
    await tester.pumpAndSettle();
    // The title and the artist are both searched.
    expect(find.text('Morning'), findsNothing);
    expect(find.text('The Sea'), findsOneWidget);
    expect(find.text('Evening'), findsOneWidget);

    await tester.tap(find.text('Evening'));
    await tester.pump();
    expect(handler.index, 2);
    expect((handler.playlist!['list'] as List).length, 3);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Nothing in your library matches.'), findsOneWidget);

    // Closing the search brings everything back.
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Morning'), findsOneWidget);
    expect(find.text('Nothing in your library matches.'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
  });
}
