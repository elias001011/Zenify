import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/main.dart' show audioHandler;
import 'package:musify/screens/library_page.dart';
import 'package:musify/screens/user_songs_page.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/local_files_service.dart';
import 'package:musify/services/settings_manager.dart';

import 'support/app_harness.dart';
import 'support/wave_test_handler.dart';

class _Handler extends WaveTestHandler {
  var plays = 0;
  @override
  Future<void> playPlaylistSong({
    Map? playlist,
    required int songIndex,
    bool? shuffle,
    bool keepGoing = false,
  }) async {
    plays++;
  }
}

void main() {
  useAppSettings();
  testWidgets('Play with an empty filter leaves the current playback alone', (
    tester,
  ) async {
    final handler = _Handler();
    audioHandler = handler;
    offlineMode.value = false;
    userLikedSongsList.value = [
      {'ytid': 'local:1', 'title': 'Song'},
    ];
    await tester.pumpWidget(localizedApp(const UserSongsPage(page: 'liked')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byTooltip('Search'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'no matching title');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Play'));
    await tester.pump();
    expect(handler.plays, 0);
    await tester.enterText(find.byType(TextField), 'Song');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(FilledButton, 'Play'));
    expect(handler.plays, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hiding local files resets the active Library filter', (
    tester,
  ) async {
    audioHandler = _Handler();
    offlineMode.value = false;
    showLocalFiles.value = true;
    localFiles.value = [
      {'ytid': 'local:1', 'title': 'Local song'},
    ];
    addTearDown(() {
      showLocalFiles.value = false;
      localFiles.value = [];
    });
    await tester.pumpWidget(localizedApp(const LibraryPage()));
    await tester.pump(const Duration(milliseconds: 500));
    final local = find.widgetWithText(FilterChip, 'Local files');
    await tester.ensureVisible(local);
    await tester.tap(local);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<FilterChip>(local).selected, isTrue);
    showLocalFiles.value = false;
    await tester.pump();
    expect(local, findsNothing);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'All'))
          .selected,
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
