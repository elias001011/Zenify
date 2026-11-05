import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:musify/services/playlists_manager.dart';

import 'support/app_harness.dart';

void main() {
  // The binding blocks real HTTP requests, so only the mock below is heard.
  TestWidgetsFlutterBinding.ensureInitialized();
  useAppSettings();

  // A YouTube playlist page with a title and no videos; 'gone' ones fail.
  final asked = <String>[];
  http.Client youtube() => MockClient((request) async {
    final id = request.url.queryParameters['list'];
    if (request.method != 'GET' || id == null) {
      return http.Response('{}', 200, request: request);
    }
    asked.add(id);
    if (id.startsWith('gone')) {
      return http.Response('', 404, request: request);
    }
    return http.Response(
      '<script id="yt-initial-data">{"metadata":{"playlistMetadataRenderer":'
      '{"title":"Title of $id"}}}</script>',
      200,
      request: request,
    );
  });

  setUp(() {
    asked.clear();
    onlinePlaylists.value = [];
    userPlaylists.value = ['PLmineA', 'PLmineB', 'PLmineC'];
  });

  test('opening a playlist asks YouTube about it and no other', () async {
    await http.runWithClient(() async {
      final playlist = await getPlaylistInfoForWidget('PLfound');

      expect(playlist?['title'], 'Title of PLfound');
      expect(asked.toSet(), {'PLfound'});
    }, youtube);
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('an added playlist is asked for alone', () async {
    await http.runWithClient(() async {
      final playlist = await getPlaylistInfoForWidget('PLmineB');

      expect(playlist?['title'], 'Title of PLmineB');
      expect(asked.toSet(), {'PLmineB'});
    }, youtube);
  }, timeout: const Timeout(Duration(seconds: 20)));

  test('a playlist that could not be asked about is not remembered', () async {
    userPlaylists.value = ['PLmineA', 'goneB'];
    await http.runWithClient(() async {
      final listed = await getUserPlaylists();

      expect(listed.map((p) => p['title']), [
        'Title of PLmineA',
        'Failed playlist',
      ]);
      expect(onlinePlaylists.value.map((p) => p['ytid']), ['PLmineA']);
    }, youtube);
  }, timeout: const Timeout(Duration(seconds: 20)));
}
