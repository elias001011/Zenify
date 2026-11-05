import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/playlist_export_service.dart';
import 'package:musify/utilities/playlist_csv_import.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

List<PlaylistCsvRow> _import(String csv) {
  final result = playlistCsvRows(parseCsv(csv));
  expect(result.problem, isNull);
  return result.rows;
}

void main() {
  group('a playlist exported by Zenify comes back the same', () {
    final songs = <Map>[
      {'ytid': 'dQw4w9WgXcQ', 'title': 'Hello, "World"', 'artist': 'A, B'},
      {'ytid': 'abcdefghijk', 'title': 'Two\nlines', 'artist': 'Line\r\nbreak'},
      {'ytid': '-abcdefghij', 'title': '=SUM(A1)', 'artist': 'Plain'},
      {'ytid': '_abcdefghi-', 'title': '+1 call', 'artist': 'Plain'},
      {'ytid': 'aaaaaaaaaaa', 'title': '-dash', 'artist': 'Plain'},
      {'ytid': 'bbbbbbbbbbb', 'title': '@home', 'artist': '=Artist'},
      {'ytid': 'ccccccccccc', 'title': "'Til Tuesday", 'artist': "'Artist"},
      {'ytid': 'ddddddddddd', 'title': "'Round", 'artist': "'90s - mix"},
      {'ytid': 'eeeeeeeeeee', 'title': 'Canção do Ão', 'artist': 'Zé Ramalho'},
      {'ytid': '', 'title': 'No id at all', 'artist': 'Someone'},
      {'title': 'No key either', 'artist': 'Someone'},
      {'ytid': 'local:3f2a', 'title': 'My own file', 'artist': 'Me'},
      {'ytid': 'short', 'title': 'Odd id', 'artist': 'Me'},
    ];
    const expectedIds = <String?>[
      'dQw4w9WgXcQ',
      'abcdefghijk',
      '-abcdefghij',
      '_abcdefghi-',
      'aaaaaaaaaaa',
      'bbbbbbbbbbb',
      'ccccccccccc',
      'ddddddddddd',
      'eeeeeeeeeee',
      null,
      null,
      null,
      null,
    ];

    test('title, artist and id of each song, in order', () {
      final rows = _import(playlistCsv(songs));

      expect(rows, hasLength(songs.length));
      for (final (i, row) in rows.indexed) {
        expect(row.index, i);
        expect(row.title, songs[i]['title'], reason: 'title of row $i');
        expect(row.artist, songs[i]['artist'], reason: 'artist of row $i');
        expect(row.ytid, expectedIds[i], reason: 'id of row $i');
      }
    });

    test('a name that is a quote plus a formula start loses the quote', () {
      // The export cannot tell it from the quote it adds itself.
      final rows = _import(
        playlistCsv([
          {'ytid': 'ggggggggggg', 'title': "'=x", 'artist': "'+y"},
        ]),
      );

      expect(rows.single.title, '=x');
      expect(rows.single.artist, '+y');
    });

    test('a title or artist in tab or CR form keeps its text', () {
      final rows = _import(
        playlistCsv([
          {'ytid': 'fffffffffff', 'title': '\tTabbed', 'artist': '\rCR'},
        ]),
      );

      expect(rows.single.title, 'Tabbed');
      expect(rows.single.artist, 'CR');
      expect(rows.single.ytid, 'fffffffffff');
    });
  });

  group('files from Spotify and Chosic', () {
    const header =
        'Track URI,Track Name,Album Name,Artist Name(s),Release Date,'
        'Duration (ms),Popularity,Genres,Album ID';

    test('give the title and artist and no id', () {
      final rows = _import(
        '$header\n'
        'spotify:track:1,Song One,Album,"Artist A, Artist B",2020,1000,5,pop,'
        'abcdefghijk\n'
        'spotify:track:2,"Song, Two",Album,Artist C,2021,2000,6,rock,'
        'lmnopqrstuv\n',
      );

      expect(rows.map((r) => r.title), ['Song One', 'Song, Two']);
      expect(rows.map((r) => r.artist), ['Artist A, Artist B', 'Artist C']);
      expect(rows.map((r) => r.ytid), [null, null]);
      expect(rows.map((r) => r.index), [0, 1]);
    });

    test('keep an apostrophe that is part of the name', () {
      final rows = _import("$header\nu,'Til Tuesday,A,'Artist,2020,1,1,x,y\n");

      expect(rows.single.title, "'Til Tuesday");
      expect(rows.single.artist, "'Artist");
    });

    test('are read with a BOM and CRLF line ends', () {
      final rows = _import(
        '﻿$header\r\n'
        'u,Song,A,Artist,2020,1,1,x,y\r\n'
        'u,Other,A,Another,2020,1,1,x,y\r\n',
      );

      expect(rows.map((r) => r.title), ['Song', 'Other']);
      expect(rows.map((r) => r.artist), ['Artist', 'Another']);
    });

    test('skip rows that are short or have no song name', () {
      final rows = _import(
        'Song,Artist\n'
        'One,A\n'
        ',B\n'
        'Short\n'
        '   ,C\n'
        'Two,D\n',
      );

      expect(rows.map((r) => r.title), ['One', 'Two']);
      expect(rows.map((r) => r.index), [0, 1]);
    });
  });

  group('parsing', () {
    test('quoted commas, quotes and new lines stay in the field', () {
      expect(parseCsv('a,"b,""c""\nd",e\r\nf,g,h'), [
        ['a', 'b,"c"\nd', 'e'],
        ['f', 'g', 'h'],
      ]);
    });

    test('empty lines are dropped and a last line needs no line end', () {
      expect(parseCsv('a,b\n\n\nc,d'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });
  });

  group('problems', () {
    test('no song or no artist column is invalid', () {
      expect(
        playlistCsvRows(parseCsv('Name,Album\nx,y\n')).problem,
        PlaylistCsvProblem.invalid,
      );
      expect(
        playlistCsvRows(parseCsv('Song,Album\nx,y\n')).problem,
        PlaylistCsvProblem.invalid,
      );
      // Columns about ids, uris and urls are not names.
      expect(
        playlistCsvRows(parseCsv('Song URL,Artist\nx,y\n')).problem,
        PlaylistCsvProblem.invalid,
      );
    });

    test('a header alone, or rows without a song, is empty', () {
      expect(
        playlistCsvRows(parseCsv('Song,Artist\n')).problem,
        PlaylistCsvProblem.empty,
      );
      expect(playlistCsvRows(parseCsv('')).problem, PlaylistCsvProblem.empty);
      expect(
        playlistCsvRows(parseCsv('Song,Artist\n,B\n')).problem,
        PlaylistCsvProblem.empty,
      );
    });
  });

  group('finding the song of a row', () {
    PlaylistCsvRow row(int index, [String? ytid]) =>
        (index: index, title: 't$index', artist: 'a', ytid: ytid);

    test('a row with an id uses the id and not the search', () async {
      final byId = <String>[];
      final searched = <int>[];
      final (song, limited) = await resolveImportRow(
        row(4, 'abcdefghijk'),
        byId: (id) async {
          byId.add(id);
          return {'ytid': id, 'title': 'by id'};
        },
        search: (row) async {
          searched.add(row.index);
          return ({'ytid': 'zzzzzzzzzzz'}, false);
        },
      );

      expect(byId, ['abcdefghijk']);
      expect(searched, isEmpty);
      expect(song, {'ytid': 'abcdefghijk', 'title': 'by id'});
      expect(limited, isFalse);
    });

    test('falls back to the search when the id lookup throws', () async {
      final searched = <int>[];
      final (song, limited) = await resolveImportRow(
        row(2, 'abcdefghijk'),
        byId: (id) async => throw Exception('unavailable'),
        search: (row) async {
          searched.add(row.index);
          return ({'ytid': 'found'}, false);
        },
      );

      expect(searched, [2]);
      expect(song, {'ytid': 'found'});
      expect(limited, isFalse);
    });

    test('falls back to the search when the id gives nothing', () async {
      for (final empty in <Map?>[<String, dynamic>{}, null]) {
        final searched = <int>[];
        final (song, _) = await resolveImportRow(
          row(1, 'abcdefghijk'),
          byId: (id) async => empty,
          search: (row) async {
            searched.add(row.index);
            return ({'ytid': 'found'}, false);
          },
        );

        expect(searched, [1]);
        expect(song, {'ytid': 'found'});
      }
    });

    test('a row without an id never asks for one', () async {
      var asked = 0;
      final (song, limited) = await resolveImportRow(
        row(0),
        byId: (id) async {
          asked++;
          return {'ytid': id};
        },
        search: (row) async => ({'ytid': 'found'}, false),
      );

      expect(asked, 0);
      expect(song, {'ytid': 'found'});
      expect(limited, isFalse);
    });

    test('the search answer is passed on, rate limit included', () async {
      final (song, limited) = await resolveImportRow(
        row(0),
        byId: (id) async => {'ytid': id},
        search: (row) async => (null, true),
      );

      expect(song, isNull);
      expect(limited, isTrue);
    });

    test('a rate limit on the id lookup stops without searching', () async {
      var searched = 0;
      final (song, limited) = await resolveImportRow(
        row(0, 'abcdefghijk'),
        byId: (id) async => throw RequestLimitExceededException('slow down'),
        search: (row) async {
          searched++;
          return ({'ytid': 'found'}, false);
        },
      );

      expect(song, isNull);
      expect(limited, isTrue);
      expect(searched, 0);
    });

    test('rows resolved together keep their positions', () async {
      final rows = [row(0, 'aaaaaaaaaaa'), row(1), row(2, 'ccccccccccc')];
      final results = await Future.wait(
        rows.map(
          (r) => resolveImportRow(
            r,
            byId: (id) async {
              // The first answers last.
              await Future<void>.delayed(
                Duration(milliseconds: id.startsWith('a') ? 20 : 0),
              );
              return id.startsWith('c') ? null : {'ytid': id};
            },
            search: (r) async => ({'ytid': 'search${r.index}'}, false),
          ),
        ),
      );

      expect(results.map((r) => r.$1!['ytid']), [
        'aaaaaaaaaaa',
        'search1',
        'search2',
      ]);
    });
  });
}
