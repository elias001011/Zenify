import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/services/song_replacement.dart';
import 'package:musify/services/unavailable_songs.dart';
import 'package:musify/widgets/playlist_page/unavailable_notice.dart';

Map song(String id) => {'ytid': id, 'title': 'Track $id', 'artist': 'Artist'};

void main() {
  late Directory directory;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('zenify_unavailable');
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });
  // Writes started under the test clock may still be pending; the process
  // ends right after, so the box is left open.
  tearDownAll(
    () => directory.delete(recursive: true).catchError((_) => directory),
  );
  setUp(() {
    offlineMode.value = false;
    userOfflineSongs.value = [];
    unavailableSongs.ids.value = {};
  });

  Widget app(Widget child) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  test('a song is unavailable until one of its downloads works', () {
    unavailableSongs.markUnavailable('a');
    expect(unavailableSongs.contains('a'), isTrue);
    expect(
      (Hive.box('userNoBackup').get('unavailableSongs') as List).contains('a'),
      isTrue,
    );
    unavailableSongs.markAvailable('a');
    expect(unavailableSongs.contains('a'), isFalse);
  });

  test('the replacement search is the artist and the title', () {
    expect(replacementQuery(song('a')), 'Artist Track a');
    expect(replacementQuery({'ytid': 'x', 'title': ' Only '}), 'Only');
    expect(replacementQuery({'ytid': 'x'}), isEmpty);
  });

  test('replacements take the place of the songs they replace', () {
    final playlist = {
      'ytid': 'custom',
      'title': 'Mine',
      'source': 'user-created',
      'list': [song('a'), song('b'), song('c'), song('d')],
    };
    userCustomPlaylists.value = [playlist];
    final replaced = replaceSongsInPlaylist(playlist, {
      'b': song('b2'),
      // Already in the playlist: the old one goes, nothing is repeated.
      'c': song('d'),
    });
    expect(replaced, 2);
    expect((playlist['list'] as List).map((s) => s['ytid']), ['a', 'b2', 'd']);
    expect(replaceSongsInPlaylist(playlist, {'zzz': song('q')}), 0);
  });

  group('the notice', () {
    final songs = [song('a'), song('b'), song('c')];
    var playlists = 0;
    UnavailableNotice notice(List<List<Map>> replaced) => UnavailableNotice(
      // A playlist of its own, as a dismissal is kept.
      playlistId: 'p${playlists++}',
      songs: songs,
      onReplace: (targets) async => replaced.add(targets),
    );

    testWidgets('counts unavailable songs and hands them to replace', (
      tester,
    ) async {
      final replaced = <List<Map>>[];
      await tester.pumpWidget(app(notice(replaced)));
      expect(find.byType(FilledButton), findsNothing);

      unavailableSongs.ids.value = {'b', 'c', 'elsewhere'};
      await tester.pump();
      expect(
        find.text('2 songs in this playlist may be unavailable'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Replace'));
      await tester.pump();
      expect(replaced.single.map((s) => s['ytid']), ['b', 'c']);
    });

    testWidgets('dismissing hides it until another song fails', (tester) async {
      await tester.pumpWidget(app(notice([])));
      unavailableSongs.ids.value = {'b'};
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Dismiss'));
      await tester.pump();
      expect(find.byType(FilledButton), findsNothing);

      unavailableSongs.ids.value = {'b', 'c'};
      await tester.pump();
      expect(
        find.text('1 song in this playlist may be unavailable'),
        findsOneWidget,
      );
    });

    testWidgets('a downloaded song, or being offline, hides it', (
      tester,
    ) async {
      await tester.pumpWidget(app(notice([])));
      unavailableSongs.ids.value = {'b'};
      userOfflineSongs.value = [song('b')];
      await tester.pump();
      expect(find.byType(FilledButton), findsNothing);

      userOfflineSongs.value = [];
      await tester.pump();
      expect(find.byType(FilledButton), findsOneWidget);
      offlineMode.value = true;
      await tester.pump();
      expect(find.byType(FilledButton), findsNothing);
    });
  });
}
