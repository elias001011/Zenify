import 'package:flutter_test/flutter_test.dart';
import 'package:musify/services/local_sync/sync_data.dart';

import 'fixtures.dart';

void main() {
  test('saved Zenify playlists and the tuning travel between devices', () {
    final a = document({
      'savedZenifyPlaylists': ['zenify:daily', 'zenify:top:ZZ'],
      'moodsTuning': {
        'excludedGenres': ['Jazz'],
        'blockedArtists': <String>[],
        'discovery': 'adventurous',
      },
    });
    final merged = (document({
      'likedSongs': [song('x')],
    })..join(copyDocument(a))).materialize();
    expect(merged['savedZenifyPlaylists'], ['zenify:daily', 'zenify:top:ZZ']);
    expect((merged['moodsTuning'] as Map)['discovery'], 'adventurous');
    expect((merged['likedSongs'] as List).single['ytid'], 'x');
  });

  test('a library that never had the Moods stays without them', () {
    // As one restored from Musify: nothing of the Moods is made up.
    final merged = document({
      'likedSongs': [song('x')],
    }).materialize();
    expect(merged.containsKey('moodsTuning'), isFalse);
    expect(merged['savedZenifyPlaylists'], isEmpty);
  });

  test('the newest tuning wins and an unsaved playlist stays unsaved', () {
    final initial = {
      'savedZenifyPlaylists': ['zenify:daily', 'zenify:new'],
      'moodsTuning': {'discovery': 'balanced'},
    };
    final a = document(initial), b = document(initial);
    final base = a.materialize();
    a.capture(
      {
        ...base,
        'savedZenifyPlaylists': ['zenify:new'],
        'moodsTuning': {'discovery': 'familiar'},
      },
      base,
      'a',
    );
    b.join(copyDocument(a));
    a.join(copyDocument(b));
    for (final doc in [a, b]) {
      final merged = doc.materialize();
      expect(merged['savedZenifyPlaylists'], ['zenify:new']);
      expect((merged['moodsTuning'] as Map)['discovery'], 'familiar');
    }
  });

  test('the Moods only reach devices that chose them', () {
    final doc = document({
      'likedSongs': [song('x')],
      'savedZenifyPlaylists': ['zenify:daily'],
    });
    final withoutMoods = SyncCategory.values.toSet()
      ..remove(SyncCategory.moods);
    final selected = doc.select(withoutMoods).materialize();
    expect(selected['savedZenifyPlaylists'], isEmpty);
    expect(selected['likedSongs'] as List, hasLength(1));
  });

  test('Musify devices are never told about Zenify-only categories', () {
    // They reject a category they don't know, so the Moods are announced
    // apart from the rest.
    expect(zenifyOnlySyncCategories, {SyncCategory.moods});
    expect(syncCategoryKeys[SyncCategory.moods], [
      'savedZenifyPlaylists',
      'moodsTuning',
    ]);
  });
}
