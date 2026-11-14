import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:musify/services/mix_analysis.dart';
import 'package:musify/services/mix_edits.dart';
import 'package:musify/services/mix_transition.dart';
import 'package:musify/widgets/mix_chip.dart';

import 'support/app_harness.dart';

void main() {
  useAppSettings(inMemory: true);
  const edit = MixEdit(
    outStart: Duration(seconds: 52),
    inStart: Duration(seconds: 2),
    length: Duration(seconds: 8),
    style: MixStyle.wave,
  );

  setUp(() async => Hive.box('settings').clear());

  test('an old backup without Mix edits is Automatic', () {
    expect(MixEditStore().get('playlist', 'a', 'b'), isNull);
  });

  test(
    'ordered pairs and playlists remain independent across reloads',
    () async {
      final store = MixEditStore();
      await store.set('one', 'a', 'b', edit);
      final reloaded = MixEditStore();
      expect(reloaded.get('one', 'a', 'b')!.toList(), edit.toList());
      expect(reloaded.get('one', 'b', 'a'), isNull);
      expect(reloaded.get('two', 'a', 'b'), isNull);
      // Separators in local-file ids cannot cause pair-key collisions.
      await store.set('one', 'a>b', 'c', edit);
      expect(store.get('one', 'a', 'b>c'), isNull);
      expect(store.get('one', 'a>b', 'c'), isNotNull);
    },
  );

  test(
    'reordering retains edits; deleting either song prunes only its pairs',
    () async {
      final store = MixEditStore();
      await store.set('one', 'a', 'b', edit);
      await store.set('one', 'b', 'c', edit);
      await store.set('two', 'a', 'b', edit);
      await store.retainSongs('one', {'c', 'b', 'a'});
      expect(store.get('one', 'a', 'b'), isNotNull);
      await store.retainSongs('one', {'a', 'b'});
      expect(store.get('one', 'a', 'b'), isNotNull);
      expect(store.get('one', 'b', 'c'), isNull);
      await store.retainSongs('one', {});
      expect(store.get('one', 'a', 'b'), isNull);
      expect(store.get('two', 'a', 'b'), isNotNull);
    },
  );

  test(
    'resetting to Auto removes the edit rather than freezing Auto',
    () async {
      final store = MixEditStore();
      await store.set('one', 'a', 'b', edit);
      await store.set('one', 'b', 'c', edit);
      await store.set('one', 'a', 'b', null);
      expect(store.get('one', 'a', 'b'), isNull);
      expect(store.get('one', 'b', 'c'), isNotNull);
    },
  );

  test('invalid backup entries fall back to Auto', () async {
    for (final value in [
      null,
      {},
      [],
      [0, 0, 8000],
      [-1, 0, 8000, 'wave'],
      [0, 0, double.nan, 'wave'],
      [0, 0, 0, 'wave'],
      [0, 0, 40001, 'wave'],
      [0, 0, 8000, 'future-style'],
      ['x', 0, 8000, 'wave'],
    ]) {
      expect(MixEdit.parse(value), isNull, reason: '$value');
    }
    await Hive.box('settings').put(MixEditStore.storageKey, 'bad');
    expect(MixEditStore().get('one', 'a', 'b'), isNull);
  });

  test('shorter replacement files cannot produce an out-of-range cue', () {
    final cue = edit.cue(
      const Duration(seconds: 54),
      const Duration(seconds: 4),
    );
    expect(cue.outStart, const Duration(seconds: 52));
    expect(cue.inStart, const Duration(seconds: 2));
    expect(cue.length, const Duration(seconds: 2));
    final tiny = edit.cue(
      const Duration(seconds: 1),
      const Duration(seconds: 1),
    );
    expect(
      tiny.outStart + tiny.length,
      lessThanOrEqualTo(const Duration(seconds: 1)),
    );
    expect(
      tiny.inStart + tiny.length,
      lessThanOrEqualTo(const Duration(seconds: 1)),
    );
  });

  test('a saved style is visible before analysis completes', () {
    expect(mixChipLabel({'ytid': 'a'}, {'ytid': 'b'}, edit: edit), 'Wave');
  });

  test('waveforms are bounded and preserve silence and relative level', () {
    final samples = Int16List.fromList([0, 0, 16384, -16384, 32767, -32767]);
    final wave = mixEnvelope(samples, bins: 3);
    expect(wave[0], 0);
    expect(wave[1], 0.5);
    expect(wave[2], closeTo(1, 0.001));
    expect(mixEnvelope(Int16List(100000)).length, 400);
    expect(mixEnvelope(Int16List(0)), isEmpty);
  });
}
