import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/localization/app_localizations.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/services/download_manager.dart';
import 'package:musify/services/playlists_manager.dart';
import 'package:musify/services/settings_manager.dart';
import 'package:musify/services/song_replacement.dart';
import 'package:musify/services/unavailable_songs.dart';
import 'package:musify/utilities/formatter.dart';
import 'package:musify/widgets/playlist_page/unavailable_notice.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

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
  var downloaded = <String>[];
  setUp(() {
    offlineMode.value = false;
    userOfflineSongs.value = [];
    unavailableSongs.reset();
    DownloadManager.instance
      ..idleMargin = const Duration(milliseconds: 20)
      ..persist = false
      ..reset();
    userCustomPlaylists.value = [];
    userPlaylistFolders.value = [];
    DownloadManager.instance.clearHistory();
    downloaded = [];
    findReplacement = (song, {Set<String> exclude = const {}}) async =>
        exclude.contains('new-${song['ytid']}')
        ? null
        : {...song, 'ytid': 'new-${song['ytid']}'};
    downloadReplacement = (song, {cancelled}) async {
      downloaded.add(song['ytid'].toString());
      return true;
    };
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
    unavailableSongs
      ..markUnavailable('a')
      ..flush();
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

  Map playlist(String id, List<String> ids) => {
    'ytid': id,
    'title': 'Playlist $id',
    'source': 'user-created',
    'list': [for (final i in ids) song(i)],
  };

  List<String> idsIn(Map playlist) => [
    for (final s in playlist['list'] as List) s['ytid'] as String,
  ];

  test('replacements take the place of the songs they replace', () {
    final mine = playlist('custom', ['a', 'b', 'c', 'd']);
    userCustomPlaylists.value = [mine];
    final replaced = replaceSongsInPlaylist(mine, {
      'b': song('b2'),
      // Already in the playlist: the old one goes, nothing is repeated.
      'c': song('d'),
    });
    expect(replaced, {'b', 'c'});
    expect(idsIn(mine), ['a', 'b2', 'd']);
    expect(replaceSongsInPlaylist(mine, {'zzz': song('q')}), isEmpty);
  });

  group('replacing unavailable songs', () {
    test(
      'swaps them in every playlist that holds them, and downloads',
      () async {
        final one = playlist('one', ['a', 'b']);
        final two = playlist('two', ['b', 'c']);
        final other = playlist('other', ['c']);
        userCustomPlaylists.value = [one, two, other];
        final entry = DownloadManager.instance.started(song('b'));
        DownloadManager.instance.failed(
          entry,
          VideoUnavailableException('gone'),
        );
        expect(unavailableSongs.contains('b'), isTrue);

        final replaced = await replaceUnavailableSongs([song('b')]);

        expect(replaced, 1);
        expect(idsIn(one), ['a', 'new-b']);
        expect(idsIn(two), ['new-b', 'c']);
        expect(idsIn(other), ['c']);
        expect(downloaded, ['new-b']);
        // No playlist holds it any more: gone from the record and the tab.
        expect(unavailableSongs.contains('b'), isFalse);
        expect(
          DownloadManager.instance.entries.value.map((e) => e.ytid),
          isNot(contains('b')),
        );
      },
    );

    test(
      'one playlist leaves the song flagged where it is still held',
      () async {
        final one = playlist('one', ['a', 'b']);
        final two = playlist('two', ['b']);
        userCustomPlaylists.value = [one, two];
        unavailableSongs.markUnavailable('b');

        expect(
          await replaceUnavailableSongs([song('b')], playlistId: 'one'),
          1,
        );

        expect(idsIn(one), ['a', 'new-b']);
        expect(idsIn(two), ['b']);
        expect(unavailableSongs.contains('b'), isTrue);
      },
    );

    test('a song nothing is found for, or no playlist holds, stays', () async {
      final one = playlist('one', ['a', 'b']);
      userCustomPlaylists.value = [one];
      findReplacement = (song, {Set<String> exclude = const {}}) async => null;
      unavailableSongs.markUnavailable('b');

      expect(await replaceUnavailableSongs([song('b'), song('x')]), 0);

      expect(idsIn(one), ['a', 'b']);
      expect(unavailableSongs.contains('b'), isTrue);
      expect(downloaded, isEmpty);
    });
  });

  test('dismissing in one playlist keeps what other playlists dismissed', () {
    unavailableSongs
      ..dismiss('a-playlist', ['x'])
      // A new session: nothing of the first is in memory.
      ..reset()
      ..dismiss('b-playlist', ['y']);
    expect(unavailableSongs.dismissed('b-playlist'), {'y'});
    unavailableSongs.reset();
    expect(unavailableSongs.dismissed('a-playlist'), {'x'});
  });

  group('swapping, with things changing', () {
    test('a song that plays after all is left alone', () async {
      userCustomPlaylists.value = [
        playlist('p', ['a', 'b']),
      ];
      // Never flagged, or flagged and then cleared by a download.
      expect(await replaceUnavailableSongs([song('b')]), 0);
      expect(idsIn(userCustomPlaylists.value.single), ['a', 'b']);
      expect(downloaded, isEmpty);
    });

    test(
      'only what is still there is swapped, counted and downloaded',
      () async {
        final mine = playlist('p', ['a', 'b']);
        userCustomPlaylists.value = [mine];
        unavailableSongs.markUnavailable('b');
        findReplacement = (original, {Set<String> exclude = const {}}) async {
          // The user removes it from the playlist while the search runs.
          mine['list'] = [song('a')];
          return {...original, 'ytid': 'new-b'};
        };

        expect(await replaceUnavailableSongs([song('b')]), 0);
        expect(idsIn(mine), ['a']);
        expect(downloaded, isEmpty);
        expect(unavailableSongs.contains('b'), isTrue);
      },
    );

    test('an edit made while searching is not undone', () async {
      userCustomPlaylists.value = [
        playlist('p', ['a', 'b']),
      ];
      unavailableSongs.markUnavailable('b');
      findReplacement = (original, {Set<String> exclude = const {}}) async {
        // An edit replaces the playlist's map: a song is added meanwhile.
        userCustomPlaylists.value = [
          playlist('p', ['a', 'b', 'c']),
        ];
        return {...original, 'ytid': 'new-b'};
      };

      expect(await replaceUnavailableSongs([song('b')]), 1);
      expect(idsIn(userCustomPlaylists.value.single), ['a', 'new-b', 'c']);
    });

    test('a song that plays during the search is left alone', () async {
      userCustomPlaylists.value = [
        playlist('p', ['a', 'b']),
      ];
      unavailableSongs.markUnavailable('b');
      findReplacement = (original, {Set<String> exclude = const {}}) async {
        unavailableSongs.markAvailable('b');
        return {...original, 'ytid': 'new-b'};
      };

      expect(await replaceUnavailableSongs([song('b')]), 0);
      expect(idsIn(userCustomPlaylists.value.single), ['a', 'b']);
      expect(downloaded, isEmpty);
    });

    test('no search at all is told apart from nothing found', () async {
      userCustomPlaylists.value = [
        playlist('p', ['a', 'b', 'c']),
      ];
      unavailableSongs
        ..markUnavailable('b')
        ..markUnavailable('c');
      findReplacement = (original, {Set<String> exclude = const {}}) async =>
          throw const ReplacementSearchFailed();

      await expectLater(
        replaceUnavailableSongs([song('b'), song('c')]),
        throwsA(isA<ReplacementSearchFailed>()),
      );
      expect(idsIn(userCustomPlaylists.value.single), ['a', 'b', 'c']);
      expect(downloaded, isEmpty);

      // One search made, even if it found nothing, is no failure of them all.
      findReplacement = (original, {Set<String> exclude = const {}}) async =>
          original['ytid'] == 'b'
          ? throw const ReplacementSearchFailed()
          : null;
      expect(await replaceUnavailableSongs([song('b'), song('c')]), 0);
    });

    test('asking twice swaps once', () async {
      userCustomPlaylists.value = [
        playlist('p', ['a', 'b']),
      ];
      unavailableSongs.markUnavailable('b');
      final both = await Future.wait([
        replaceUnavailableSongs([song('b')]),
        replaceUnavailableSongs([song('b')]),
      ]);
      expect(both.reduce((a, b) => a + b), 1);
      expect(downloaded, ['new-b']);
    });

    test('a song kept in the liked songs stays flagged', () async {
      userCustomPlaylists.value = [
        playlist('p', ['a', 'b']),
      ];
      userLikedSongsList.value = [song('b')];
      addTearDown(() => userLikedSongsList.value = []);
      unavailableSongs.markUnavailable('b');

      expect(await replaceUnavailableSongs([song('b')]), 1);
      expect(unavailableSongs.contains('b'), isTrue);
    });

    test('open pages are told that songs were swapped', () async {
      userCustomPlaylists.value = [
        playlist('p', ['a', 'b']),
      ];
      unavailableSongs.markUnavailable('b');
      final before = replacedSongs.value;
      await replaceUnavailableSongs([song('b')]);
      expect(replacedSongs.value, before + 1);
    });
  });

  group('what flags a song', () {
    test('only an unplayable download does, and a download clears it', () {
      final manager = DownloadManager.instance;
      manager.failed(manager.started(song('n')), StateError('network'));
      expect(unavailableSongs.contains('n'), isFalse);

      manager.failed(
        manager.started(song('u')),
        VideoUnavailableException('x'),
      );
      expect(unavailableSongs.contains('u'), isTrue);

      manager.finished(manager.started(song('u')));
      expect(unavailableSongs.contains('u'), isFalse);
    });
  });

  group('the notice', () {
    final swaps = <(List<String>, String?)>[];
    setUp(() {
      swaps.clear();
      // Under the fake clock of widget tests nothing may be written.
      unavailableSongs.persist = false;
    });
    tearDown(() => unavailableSongs.persist = true);

    UnavailableNotice notice() => UnavailableNotice(
      playlistId: 'p',
      songs: [song('a'), song('b'), song('c')],
      replace: (songs, {playlistId}) async {
        swaps.add(([for (final s in songs) s['ytid'] as String], playlistId));
        return songs.length;
      },
    );

    testWidgets('counts unavailable songs and swaps them', (tester) async {
      await tester.pumpWidget(app(notice()));
      expect(find.byType(FilledButton), findsNothing);

      unavailableSongs.ids.value = {'b', 'c', 'elsewhere'};
      await tester.pump();
      expect(
        find.text('2 songs in this playlist may be unavailable'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Replace'));
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(swaps.single.$1, ['b', 'c']);
      expect(swaps.single.$2, 'p');
      // Lets the message go.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('a search that cannot be made leaves Replace usable', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(
          UnavailableNotice(
            playlistId: 'p',
            songs: [song('a'), song('b')],
            replace: (songs, {playlistId}) async =>
                throw const ReplacementSearchFailed(),
          ),
        ),
      );
      unavailableSongs.ids.value = {'b'};
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Replace'));
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('dismissing hides it until another song fails', (tester) async {
      await tester.pumpWidget(app(notice()));
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

    testWidgets('waits until every download is over, and for a margin', (
      tester,
    ) async {
      final manager = DownloadManager.instance;
      await tester.pumpWidget(app(notice()));
      unavailableSongs.ids.value = {'b'};
      // Another playlist's download is running: this one may still lose songs.
      final entry = manager.queued(song('z'));
      await tester.pump();
      expect(find.byType(FilledButton), findsNothing);

      manager.finished(entry);
      await tester.pump(const Duration(milliseconds: 5));
      expect(find.byType(FilledButton), findsNothing);
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('a downloaded song, or being offline, hides it', (
      tester,
    ) async {
      await tester.pumpWidget(app(notice()));
      unavailableSongs.ids.value = {'b'};
      await tester.pump();
      expect(find.byType(FilledButton), findsOneWidget);

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

  group('what counts as the same recording', () {
    final original = {
      'title': 'Bohemian Rhapsody',
      'artist': 'Queen',
      'duration': 355,
    };
    Map candidate(
      String title, {
      String artist = 'Queen',
      String? channel,
      int? seconds = 355,
    }) => {
      'title': title,
      'artist': artist,
      'videoAuthor': channel ?? artist,
      'duration': seconds,
    };

    test('accepts another upload of it', () {
      expect(isSameRecording(original, candidate('Bohemian Rhapsody')), isTrue);
      expect(
        isSameRecording(
          original,
          candidate(
            'Bohemian Rhapsody',
            seconds: 359,
            channel: 'Queen Official',
          ),
        ),
        isTrue,
      );
      expect(
        isSameRecording(
          original,
          candidate('Bohemian Rhapsody', seconds: null),
        ),
        isTrue,
      );
      // The title the app keeps has no "(Official Video)" any more.
      expect(
        isSameRecording(
          original,
          candidate(formatSongTitle('Bohemian Rhapsody (Official Video)')),
        ),
        isTrue,
      );
    });

    test('turns down other songs, other artists and other lengths', () {
      expect(
        isSameRecording(original, candidate('Another One Bites')),
        isFalse,
      );
      expect(
        isSameRecording(
          original,
          candidate('Bohemian Rhapsody', artist: 'Muse'),
        ),
        isFalse,
      );
      expect(
        isSameRecording(original, candidate('Bohemian Rhapsody', seconds: 240)),
        isFalse,
      );
      expect(isSameRecording({'ytid': 'x'}, candidate('Anything')), isFalse);
    });

    test('turns down covers and remixes, even as long as the original', () {
      // Naming the artist in the title is no credit: the channel is Muse.
      expect(
        isSameRecording(
          original,
          candidate('Bohemian Rhapsody (Queen cover)', artist: 'Muse'),
        ),
        isFalse,
      );
      // A remix says more than the title does.
      expect(
        isSameRecording(original, candidate('Bohemian Rhapsody (Remix)')),
        isFalse,
      );
      expect(
        isSameRecording(
          original,
          candidate('Bohemian Rhapsody Live at Wembley'),
        ),
        isFalse,
      );
    });

    test('the artist in the title is fine, when the channel is the artist', () {
      expect(
        isSameRecording(original, candidate('Queen Bohemian Rhapsody')),
        isTrue,
      );
    });
  });
}
