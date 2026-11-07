import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:musify/screens/replace_review_page.dart';
import 'package:musify/services/song_replacement.dart';

import 'support/app_harness.dart';

Map song(String id, [String artist = 'Artist']) => {
  'ytid': id,
  'title': 'Track $id',
  'artist': artist,
};

void main() {
  setUpAll(() async {
    final directory = await Directory.systemTemp.createTemp('zenify_review');
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });

  Map<String, Map>? result;
  var closed = false;

  Future<void> open(
    WidgetTester tester,
    ReplacementPlan plan, {
    Future<List<Map>> Function(String query)? search,
    ReviewKind kind = ReviewKind.replace,
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    result = null;
    closed = false;
    await tester.pumpWidget(
      localizedApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<Map<String, Map>>(
                MaterialPageRoute(
                  builder: (_) => ReplaceReviewPage(
                    plan: plan,
                    kind: kind,
                    search: search ?? (query) async => [],
                  ),
                ),
              );
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  ReplacementPlan plan(Map<String, Map> found, {List<String>? ids}) =>
      ReplacementPlan(
        songs: [for (final id in ids ?? found.keys) song(id)],
        found: found,
        playlistIds: {'p'},
      );

  testWidgets('shows each song beside its replacement and accepts them', (
    tester,
  ) async {
    await open(tester, plan({'a': song('a2'), 'b': song('b2')}));
    expect(find.text('Review replacements'), findsOneWidget);
    expect(find.text('Track a'), findsOneWidget);
    expect(find.text('Track a2'), findsOneWidget);
    expect(find.text('Track b2'), findsOneWidget);

    await tester.tap(find.text('Replace 2 songs'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(closed, isTrue);
    expect(result!.keys, {'a', 'b'});
    expect(result!['a']!['ytid'], 'a2');
  });

  testWidgets('cancelling swaps nothing', (tester) async {
    await open(tester, plan({'a': song('a2')}));
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(closed, isTrue);
    expect(result, isNull);
  });

  testWidgets(
    'a song with no replacement says so and can be searched by hand',
    (tester) async {
      String? asked;
      await open(
        tester,
        plan({'a': song('a2')}, ids: ['a', 'b']),
        search: (query) async {
          asked = query;
          return [song('b-hand')];
        },
      );
      expect(find.text('No replacement found'), findsOneWidget);
      // Only the one found is counted.
      expect(find.text('Replace 1 song'), findsOneWidget);

      await tester.tap(find.text('Search manually').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 1));
      expect(asked, 'Artist Track b');
      expect(find.text('Track b-hand'), findsOneWidget);

      await tester.tap(find.byIcon(FluentIcons.checkmark_24_regular).last);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // Chosen by hand: counted, and labelled so.
      expect(find.text('Chosen by you'), findsOneWidget);
      expect(find.text('Replace 2 songs'), findsOneWidget);
    },
  );

  testWidgets('manual search never offers the song itself, nor one held', (
    tester,
  ) async {
    await open(
      tester,
      ReplacementPlan(
        songs: [song('a')],
        found: const {},
        playlistIds: {'p'},
        held: {'a', 'held'},
      ),
      search: (query) async => [song('a'), song('held'), song('fresh')],
    );
    await tester.tap(find.text('Search manually'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Track fresh'), findsOneWidget);
    expect(find.text('Track held'), findsNothing);
    // Only the row's own "Unavailable" song carries this title.
    expect(find.text('Track a'), findsOneWidget);
  });

  testWidgets('an automatic match can be refused', (tester) async {
    await open(tester, plan({'a': song('a2'), 'b': song('b2')}));
    expect(find.text('Replace 2 songs'), findsOneWidget);
    await tester.tap(find.text("Don't replace").first);
    await tester.pump();
    expect(find.text("Won't be replaced"), findsOneWidget);
    expect(find.text('Replace 1 song'), findsOneWidget);
    await tester.tap(find.text('Replace 1 song'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(result!.keys, {'b'});
  });

  testWidgets('a song that could not be searched says so', (tester) async {
    await open(
      tester,
      ReplacementPlan(
        songs: [song('a'), song('b')],
        found: {'a': song('a2')},
        playlistIds: {'p'},
        notSearched: {'b'},
      ),
    );
    expect(find.text('The search failed. Try by hand'), findsOneWidget);
    expect(find.text('No replacement found'), findsNothing);
  });

  testWidgets('songs of an imported file: suggestions, a prefilled search, '
      'copy and finish', (tester) async {
    String? first;
    await open(
      tester,
      ReplacementPlan(
        songs: [song('file:0', 'Singer'), song('file:1', 'Other')],
        // The automatic search found one of them.
        found: {'file:1': song('suggested')},
        playlistIds: {'p'},
        held: {'kept'},
      ),
      kind: ReviewKind.missing,
      search: (query) async {
        first ??= query;
        return [song('kept'), song('hit')];
      },
    );
    expect(find.text('Songs not found'), findsOneWidget);
    expect(find.text('In your file'), findsNWidgets(2));
    expect(find.text('Track file:0'), findsOneWidget);
    expect(find.text('No match chosen yet'), findsOneWidget);
    expect(find.text('Track suggested'), findsOneWidget);

    await tester.tap(find.text('Search manually').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));
    // The name of the song is in the search bar already, and one the playlist
    // holds is not offered.
    expect(first, 'Singer Track file:0');
    expect(find.text('Track hit'), findsOneWidget);
    expect(find.text('Track kept'), findsNothing);

    await tester.tap(find.byIcon(FluentIcons.checkmark_24_regular).last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // The suggestion (the second row) can be left out.
    await tester.tap(find.text("Don't add").last);
    await tester.pump();
    expect(find.text('Track suggested'), findsNothing);

    await tester.tap(find.text('Finish'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(result!.keys, {'file:0'});
    expect(result!['file:0']!['ytid'], 'hit');
  });

  testWidgets('copy puts the songs still without a match on the clipboard', (
    tester,
  ) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await open(
      tester,
      ReplacementPlan(
        songs: [song('file:0', 'Singer'), song('file:1', 'Other')],
        found: {'file:1': song('suggested')},
        playlistIds: {'p'},
      ),
      kind: ReviewKind.missing,
    );
    await tester.tap(find.text('Copy'));
    await tester.pump();
    // Only the one with no match is left to look for elsewhere.
    expect(clipboard, 'Track file:0 - Singer');
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('finishing with nothing chosen adds nothing', (tester) async {
    await open(
      tester,
      ReplacementPlan(
        songs: [song('file:0')],
        found: const {},
        playlistIds: {'p'},
      ),
      kind: ReviewKind.missing,
    );
    await tester.tap(find.text('Finish'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(closed, isTrue);
    expect(result, isEmpty);
  });
}
