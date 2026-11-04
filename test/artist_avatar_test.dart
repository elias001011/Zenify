import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/widgets/song_artwork.dart';
import 'package:musify/widgets/top_artists_card.dart';

void main() {
  Future<void> show(WidgetTester tester, Map? song) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: ArtistAvatar(song))),
    ),
  );

  testWidgets('an artist is shown by the cover of a song, drawn round', (
    tester,
  ) async {
    await show(tester, {
      'ytid': 'a',
      'title': 'Song',
      'artist': 'Artist',
      'highResImage': 'https://example.com/high.jpg',
      'lowResImage': 'https://example.com/low.jpg',
    });

    final artwork = tester.widget<SongArtworkWidget>(
      find.byType(SongArtworkWidget),
    );
    // The same cover the song has everywhere else, not its small thumbnail.
    expect(artwork.metadata.artUri.toString(), 'https://example.com/high.jpg');
    expect(artwork.size, ArtistTile.artworkSize);
    expect(artwork.borderRadius, ArtistTile.artworkSize / 2);
  });

  testWidgets('without a song it is a circle with a person', (tester) async {
    await show(tester, null);

    expect(find.byType(SongArtworkWidget), findsNothing);
    expect(find.byIcon(FluentIcons.person_24_regular), findsOneWidget);
  });
}
