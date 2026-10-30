import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_music_explode_dart/youtube_music_explode_dart.dart';

/// Answers every request with a trimmed YouTube Music response recorded on
/// 30/10/2026, and keeps what was asked.
class _RecordedClient extends YoutubeHttpClient {
  _RecordedClient(this.fixture);

  final String fixture;
  final requests = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>> sendPost(
    String action,
    Map<String, dynamic> data, {
    Map<String, String>? headers,
    bool validate = false,
  }) async {
    requests.add((action, data));
    return jsonDecode(
      File('test/fixtures/ytm/$fixture.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  }
}

void main() {
  test('a radio lists its tracks with their kind and artist', () async {
    final http = _RecordedClient('radio');
    final radio = await MusicClient(http)
        .getRadio('Zi_XLOBDo_Y', country: 'BR');

    expect(radio.map((t) => t.video.id.value), [
      'Zi_XLOBDo_Y',
      'oRdxUFDoQe0',
      'I_izvAbhExY',
    ]);
    final first = radio.first;
    expect(first.video.title, 'Billie Jean');
    expect(first.video.author, 'Michael Jackson');
    expect(first.video.duration, const Duration(minutes: 4, seconds: 56));
    expect(first.type, MusicVideoType.officialVideo);
    expect(first.artistId, startsWith('UC'));
    // A video's byline holds its views, not an album.
    expect(first.album, isNull);
    expect(first.thumbnailUrl, contains('ytimg'));

    final (action, body) = http.requests.single;
    expect(action, 'next');
    expect(body['playlistId'], 'RDAMVMZi_XLOBDo_Y');
    expect((body['context'] as Map)['client']['gl'], 'BR');
  });

  test('playlist rows tell songs from videos and keep the album', () async {
    final tracks = await MusicClient(_RecordedClient('playlist'))
        .getPlaylistTracks('VLRDCLAK5uy_nBE4bLuBHUXWZrF59ZrkPEToKt8M_I3Vc');

    expect(tracks, hasLength(2));
    expect(tracks[0].video.title, 'Your Other Life');
    expect(tracks[0].type, MusicVideoType.officialVideo);
    expect(tracks[0].album, isNull);
    expect(tracks[1].video.title, 'I Wish I Was');
    expect(tracks[1].video.author, 'The Avett Brothers');
    expect(tracks[1].type, MusicVideoType.song);
    expect(tracks[1].album, 'True Sadness');
    expect(tracks[1].video.duration, const Duration(minutes: 5, seconds: 17));
  });

  test('moods come before genres, each with its params', () async {
    final moods = await MusicClient(_RecordedClient('moods')).getMoods();

    expect(moods.where((m) => !m.isGenre).map((m) => m.title), [
      'Chill',
      'Commute',
    ]);
    expect(moods.where((m) => m.isGenre), hasLength(2));
    expect(moods.every((m) => m.params.isNotEmpty), isTrue);
  });

  test('mood playlists keep their shelf and drop the VL prefix', () async {
    final playlists = await MusicClient(_RecordedClient('mood_playlists'))
        .getMoodPlaylists('params');

    expect(playlists.map((p) => p.title), [
      'Coffee Shop Blend',
      'Cafecito & Chill',
      'Pop Gold',
      'Soft Rock Ballads',
    ]);
    expect(playlists.first.id, 'RDCLAK5uy_nBE4bLuBHUXWZrF59ZrkPEToKt8M_I3Vc');
    expect(playlists.first.shelf, 'Coffee shop blends');
    expect(playlists[2].shelf, 'Unwind + explore');
  });

  test('charts list the chart playlists of a country', () async {
    final http = _RecordedClient('charts');
    final charts = await MusicClient(http).getCharts();

    expect(charts.map((p) => p.title), [
      'Daily Top Music Videos - Global',
      'Top 100 Music Videos Global',
    ]);
    expect(http.requests.single.$2['formData'], {
      'selectedValues': ['ZZ'],
    });
  });
}
