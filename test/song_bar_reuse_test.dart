import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/services/common_services.dart';
import 'package:musify/widgets/overflow_menu_button.dart';
import 'package:musify/widgets/song_bar.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings();

  Map song(String id) => {
    'ytid': id,
    'title': 'Song $id',
    'artist': 'Artist',
    'lowResImage': 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
  };

  Widget row(Map song) => localizedApp(Scaffold(body: SongBar(song, false)));

  testWidgets('a row handed another song shows that song, liked or not', (
    tester,
  ) async {
    userLikedSongsList.value = [song('a')];
    // The menu's rows overflow in the test font; that is not what is tested.
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.toString().contains('overflowed')) onError!(details);
    };
    addTearDown(() => FlutterError.onError = onError);
    Future<bool> menuOffersUnlike(Map shown) async {
      await tester.pumpWidget(row(shown));
      await tester.tap(find.byWidgetPredicate((w) => w is OverflowMenuButton));
      await tester.pumpAndSettle();
      final liked = find.text('Remove from liked songs').evaluate().isNotEmpty;
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      return liked;
    }

    expect(await menuOffersUnlike(song('a')), isTrue);
    // The same row (no key), now for a song that is not liked.
    expect(find.text('Song a'), findsOneWidget);
    expect(await menuOffersUnlike(song('b')), isFalse);
    expect(find.text('Song b'), findsOneWidget);
    expect(await menuOffersUnlike(song('a')), isTrue);
  });
}
