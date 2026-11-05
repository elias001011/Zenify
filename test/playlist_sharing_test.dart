import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/playlist_sharing.dart';

String encode(Object? value) =>
    base64Url.encode(utf8.encode(json.encode(value)));

List<String> ids(int count) => [
  for (var i = 0; i < count; i++) i.toString().padLeft(11, 'a'),
];

Map<String, dynamic> link({
  Object? title = 'Road trip',
  Object? list,
  Map<String, dynamic> extra = const {},
}) => {
  if (title != null) 'title': title,
  'source': 'user-created',
  'list': list ?? ['dQw4w9WgXcQ', 'a_b-c1D2e3F'],
  ...extra,
};

Map<String, dynamic>? parse(Object? value) =>
    PlaylistSharingService.parseCompactPlaylist(encode(value));

void main() {
  group('valid links', () {
    test('round-trips title, image, source and list', () {
      final parsed = parse(link(extra: {'image': 'https://example.com/a.jpg'}));
      expect(parsed, {
        'title': 'Road trip',
        'image': 'https://example.com/a.jpg',
        'source': 'user-created',
        'list': ['dQw4w9WgXcQ', 'a_b-c1D2e3F'],
      });
      expect(parsed!['list'], isA<List<String>>());
    });

    test('drops unknown keys and forces the source', () {
      final parsed = parse(
        link(
          extra: {
            'ytid': 'custom-123',
            'isArtist': true,
            'isAlbum': true,
            'foo': {'bar': 1},
            'source': 'youtube',
          },
        ),
      );
      expect(parsed!.keys.toSet(), {'title', 'source', 'list'});
      expect(parsed['source'], 'user-created');
    });

    test('accepts exactly 1000 songs and rejects 1001', () {
      expect(parse(link(list: ids(1000)))!['list'], hasLength(1000));
      expect(parse(link(list: ids(1001))), isNull);
    });
  });

  group('invalid links', () {
    test('rejects text that is not base64 or not JSON', () {
      expect(PlaylistSharingService.parseCompactPlaylist('%%%'), isNull);
      expect(PlaylistSharingService.parseCompactPlaylist(''), isNull);
      expect(
        PlaylistSharingService.parseCompactPlaylist(
          base64Url.encode(utf8.encode('not json')),
        ),
        isNull,
      );
      expect(
        PlaylistSharingService.parseCompactPlaylist(
          base64Url.encode([0xff, 0xfe, 0xfd]),
        ),
        isNull,
      );
    });

    test('rejects JSON that is not an object', () {
      expect(parse(['a', 'b']), isNull);
      expect(parse('text'), isNull);
      expect(parse(42), isNull);
      expect(parse(null), isNull);
    });

    test('rejects a missing or non-list "list"', () {
      expect(parse({'title': 'T'}), isNull);
      expect(parse(link(list: 'dQw4w9WgXcQ')), isNull);
      expect(parse(link(list: {'a': 'dQw4w9WgXcQ'})), isNull);
    });

    test('rejects an empty list', () {
      expect(parse(link(list: <String>[])), isNull);
    });

    test('rejects a non-string entry', () {
      expect(parse(link(list: ['dQw4w9WgXcQ', 5])), isNull);
      expect(parse(link(list: ['dQw4w9WgXcQ', null])), isNull);
      expect(
        parse(
          link(
            list: [
              {'ytid': 'dQw4w9WgXcQ'},
            ],
          ),
        ),
        isNull,
      );
    });

    test('rejects entries that are not an 11-character id', () {
      for (final bad in [
        'short',
        'dQw4w9WgXcQ1',
        'dQw4w9 gXcQ',
        'dQw4w9WgXc!',
        'https://youtu.be/dQw4w9WgXcQ',
        ' dQw4w9WgXcQ',
        'dQw4w9WgXcQ\n',
      ]) {
        expect(parse(link(list: ['dQw4w9WgXcQ', bad])), isNull, reason: bad);
      }
    });
  });

  group('title', () {
    test('must be a non-empty string', () {
      expect(parse(link(title: null)), isNull);
      expect(parse(link(title: 5)), isNull);
      expect(parse(link(title: ['a'])), isNull);
      expect(parse(link(title: '')), isNull);
      expect(parse(link(title: '   ')), isNull);
      expect(parse(link(title: '\u0000\u0007\u001f\u007f\u0085')), isNull);
    });

    test('loses control and bidi characters', () {
      const unsafe = [
        0x00, 0x0A, 0x1F, 0x7F, 0x85, 0x9F, // controls
        0x200B, 0x200F, 0x202A, 0x202E, 0x2066, 0x2069, 0xFEFF, // invisible
      ];
      for (final code in unsafe) {
        final title = 'My${String.fromCharCode(code)} mix';
        expect(parse(link(title: title))!['title'], 'My mix', reason: '$code');
      }
    });

    test('keeps ordinary Unicode and inner spacing', () {
      expect(parse(link(title: '  Café  ☕  日本 '))!['title'], 'Café  ☕  日本');
    });

    test('is cut to 100 characters', () {
      expect(parse(link(title: 'x' * 100))!['title'], 'x' * 100);
      expect(parse(link(title: 'x' * 500))!['title'], 'x' * 100);
    });
  });

  group('image', () {
    String? imageOf(Object? image) {
      final parsed = parse(link(extra: {'image': image}));
      expect(parsed, isNotNull, reason: 'the playlist stays valid');
      return parsed!['image'] as String?;
    }

    test('is kept for http and https', () {
      expect(imageOf('http://example.com/a.png'), 'http://example.com/a.png');
      expect(imageOf('https://example.com/a.png'), 'https://example.com/a.png');
    });

    test('is dropped for other schemes and relative paths', () {
      for (final bad in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'content://media/external/1',
        '/storage/emulated/0/a.jpg',
        'a.jpg',
        'https:///no-host',
        '',
      ]) {
        expect(imageOf(bad), isNull, reason: bad);
      }
    });

    test('is dropped when it is not a string or is too long', () {
      expect(imageOf(5), isNull);
      expect(imageOf(['https://example.com/a.png']), isNull);
      expect(imageOf('https://example.com/${'a' * 2048}'), isNull);
    });

    test('allows exactly 2048 characters', () {
      final url = 'https://example.com/${'a' * (2048 - 20)}';
      expect(url.length, 2048);
      expect(imageOf(url), url);
    });
  });
}
