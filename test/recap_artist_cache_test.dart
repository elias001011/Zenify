import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/artist_service.dart';
import 'package:musify/services/data_manager.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings();

  test('a cached artist profile is shared by name and artist page', () async {
    await cacheArtistProfile({
      'ytid': 'UC1234567890123456789012',
      'title': 'Cached Artist',
      'image': 'https://example.com/artist.jpg',
      'topSongs': <Map>[],
    });
    await addOrUpdateData<String>(
      'cache',
      'artist_source_v2_cached%20artist_source-song',
      'UC1234567890123456789012',
    );
    final recap = await getCachedArtistProfileForSong(
      ' cached artist ',
      'source-song',
    );
    expect(
      await getCachedArtistProfileForSong('Cached Artist', 'other-song'),
      isNull,
    );
    await cacheArtistProfile({
      'ytid': 'UC9876543210987654321098',
      'title': 'Cached Artist',
      'image': 'https://example.com/other.jpg',
    });
    await addOrUpdateData<String>(
      'cache',
      'artist_source_v2_cached%20artist_other-song',
      'UC9876543210987654321098',
    );
    final other = await getCachedArtistProfileForSong(
      'Cached Artist',
      'other-song',
    );
    expect(other?['image'], 'https://example.com/other.jpg');
    expect(recap?['image'], 'https://example.com/artist.jpg');
    final page = await getArtistProfile(
      'Cached Artist',
      preferredName: 'Cached Artist',
      sourceSongId: 'source-song',
    );
    expect(page?['ytid'], recap?['ytid']);
    expect(page?['image'], recap?['image']);
  });
}
