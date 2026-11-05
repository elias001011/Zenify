import 'dart:io';
import 'dart:typed_data';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/utilities/playlist_dialogs.dart';

import 'support/app_harness.dart';

/// A button that opens the dialog with what the test gives it.
Widget _app({Map? song, List<Map>? songs}) => localizedApp(
  Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () =>
            showAddToPlaylistDialog(context, song: song, songs: songs),
        child: const Text('open'),
      ),
    ),
  ),
);

Future<void> _open(WidgetTester tester, Widget app) async {
  await tester.pumpWidget(app);
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  late Directory dir;
  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('zenify_add_to_playlist');
    Hive.init(dir.path);
    for (final box in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(box, bytes: Uint8List(0));
    }
  });
  tearDownAll(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });
  setUp(() {
    userLikedSongsList.value = [];
    userPlaylistFolders.value = [];
    userCustomPlaylists.value = [
      {'ytid': 'p1', 'title': 'Road trip', 'list': []},
      {
        'ytid': 'p2',
        'title': 'Focus',
        'list': [
          {'ytid': 'a', 'title': 'Song A'},
        ],
      },
    ];
  });

  const song = {'ytid': 'a', 'title': 'Song A', 'artist': 'Artist'};

  testWidgets('a song gets the liked songs above its playlists', (
    tester,
  ) async {
    await _open(tester, _app(song: song));
    expect(find.text('Liked songs'), findsOneWidget);
    expect(find.text('Road trip'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Liked songs')).dy,
      lessThan(tester.getTopLeft(find.text('Road trip')).dy),
    );
    // The liked songs and the playlist without the song: a plus; the one with
    // it: a check.
    expect(find.byIcon(FluentIcons.add_circle_24_regular), findsNWidgets(2));
    expect(find.byIcon(FluentIcons.checkmark_circle_24_filled), findsOneWidget);
    expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsNothing);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Focus'),
          matching: find.byType(InkWell),
        ),
        matching: find.byIcon(FluentIcons.checkmark_circle_24_filled),
      ),
      findsOneWidget,
    );
  });

  testWidgets('one tap likes the song and closes the dialog', (tester) async {
    await _open(tester, _app(song: song));
    await tester.tap(find.text('Liked songs'));
    await tester.pumpAndSettle();
    expect(userLikedSongsList.value.map((s) => s['ytid']), ['a']);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Added to liked songs'), findsOneWidget);
  });

  testWidgets('a liked song shows it, and the same tap takes the like back', (
    tester,
  ) async {
    userLikedSongsList.value = [song];
    await _open(tester, _app(song: song));
    // The liked songs and the playlist that has the song.
    expect(
      find.byIcon(FluentIcons.checkmark_circle_24_filled),
      findsNWidgets(2),
    );
    await tester.tap(find.text('Liked songs'));
    await tester.pumpAndSettle();
    expect(userLikedSongsList.value, isEmpty);
    expect(find.text('Removed from liked songs'), findsOneWidget);
  });

  testWidgets('many songs, and local files, have no liked songs row', (
    tester,
  ) async {
    await _open(
      tester,
      _app(
        songs: [
          song,
          {'ytid': 'b', 'title': 'Song B'},
        ],
      ),
    );
    expect(find.text('Liked songs'), findsNothing);
    expect(find.text('Road trip'), findsOneWidget);
    // Many songs: no way to say "in it", so the rows keep their chevron.
    expect(find.byIcon(FluentIcons.chevron_right_24_regular), findsNWidgets(2));
    expect(find.byIcon(FluentIcons.checkmark_circle_24_filled), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await _open(tester, _app(song: {'ytid': 'local:/a.mp3', 'title': 'Local'}));
    expect(find.text('Liked songs'), findsNothing);
    expect(find.text('Road trip'), findsOneWidget);
  });

  testWidgets('with no playlists the liked songs are still there', (
    tester,
  ) async {
    userCustomPlaylists.value = [];
    await _open(tester, _app(song: song));
    expect(find.text('Liked songs'), findsOneWidget);
    expect(find.text('Road trip'), findsNothing);
  });
}
