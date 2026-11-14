import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:musify/services/mix_transition.dart';

/// Only deliberate edits are stored. Auto remains a calculation, so new
/// versions of the analyser improve existing playlists too.
class MixEdit {
  const MixEdit({
    required this.outStart,
    required this.inStart,
    required this.length,
    required this.style,
    this.volume,
    this.eq,
    this.filter,
    this.tempoRatio = 1,
  });

  factory MixEdit.fromCue(MixCue cue) => MixEdit(
    outStart: cue.outStart,
    inStart: cue.inStart,
    length: cue.length,
    style: cue.style,
    volume: cue.volume,
    eq: cue.eq,
    filter: cue.filter,
    tempoRatio: cue.tempoRatio,
  );

  final Duration outStart;
  final Duration inStart;
  final Duration length;
  final MixStyle style;
  final MixVolume? volume;
  final MixEq? eq;
  final MixFilter? filter;
  final double tempoRatio;

  /// Bound old edits to the actual files, including a replacement file with
  /// the same id but a shorter duration.
  MixCue cue(Duration duration, Duration? coming) {
    final total = max(1, duration.inMilliseconds);
    final incoming = coming == null ? null : max(1, coming.inMilliseconds);
    final out = outStart.inMilliseconds.clamp(0, total - 1);
    final into = inStart.inMilliseconds
        .clamp(0, max(0, (incoming ?? 40001) - 1))
        .toInt();
    final available = min(
      total - out,
      (((incoming ?? (into + 40000)) - into) / tempoRatio).floor(),
    );
    return MixCue(
      outStart: Duration(milliseconds: out),
      inStart: Duration(milliseconds: into),
      length: Duration(
        milliseconds: length.inMilliseconds
            .clamp(1, max(1, min(40000, available)))
            .toInt(),
      ),
      style: style,
      volume: volume,
      eq: eq,
      filter: filter,
      tempoRatio: tempoRatio,
    );
  }

  List<Object?> toList() => [
    outStart.inMilliseconds,
    inStart.inMilliseconds,
    length.inMilliseconds,
    style.name,
    volume?.name,
    eq?.name,
    filter?.name,
    tempoRatio,
  ];

  static MixEdit? parse(dynamic value) {
    if (value is! List || (value.length != 4 && value.length != 8)) return null;
    if (value.take(3).any((v) => v is! int || v < 0)) return null;
    if (value[2] < 1 || value[2] > 40000) return null;
    final styles = MixStyle.values.where((s) => s.name == value[3]);
    if (styles.isEmpty) return null;
    T? option<T extends Enum>(List<T> options, dynamic name) =>
        options.where((v) => v.name == name).firstOrNull;
    if (value.length == 8 &&
        (value[7] is! num ||
            !(value[7] as num).toDouble().isFinite ||
            value[7] < 0.94 ||
            value[7] > 1.06))
      return null;
    return MixEdit(
      volume: value.length == 8 ? option(MixVolume.values, value[4]) : null,
      eq: value.length == 8 ? option(MixEq.values, value[5]) : null,
      filter: value.length == 8 ? option(MixFilter.values, value[6]) : null,
      tempoRatio: value.length == 8 ? (value[7] as num).toDouble() : 1,
      outStart: Duration(milliseconds: value[0]),
      inStart: Duration(milliseconds: value[1]),
      length: Duration(milliseconds: value[2]),
      style: styles.first,
    );
  }
}

final mixEdits = MixEditStore();

/// Keys use ordered song ids, never row indices. Reordering retains an edit;
/// removing either song prunes it. The optional settings key travels in the
/// existing Hive backup, without changing the Musify backup format.
class MixEditStore {
  static const storageKey = 'mixTransitionsByPlaylist';
  final changes = ValueNotifier<int>(0);

  String _pair(String from, String to) => jsonEncode([from, to]);

  Map _all() {
    final stored = Hive.box('settings').get(storageKey);
    return stored is Map ? Map.of(stored) : {};
  }

  MixEdit? get(String? playlist, String? from, String? to) {
    if (playlist == null || from == null || to == null) return null;
    final edits = _all()[playlist];
    return edits is Map ? MixEdit.parse(edits[_pair(from, to)]) : null;
  }

  Future<void> set(
    String playlist,
    String from,
    String to,
    MixEdit? edit,
  ) async {
    final all = _all();
    final edits = all[playlist] is Map
        ? Map.of(all[playlist])
        : <dynamic, dynamic>{};
    final pair = _pair(from, to);
    if (edit == null) {
      edits.remove(pair);
    } else {
      edits[pair] = edit.toList();
    }
    if (edits.isEmpty) {
      all.remove(playlist);
    } else {
      all[playlist] = edits;
    }
    await Hive.box('settings').put(storageKey, all);
    changes.value++;
  }

  Future<void> retainSongs(String playlist, Set<String> songs) async {
    final all = _all();
    final stored = all[playlist];
    if (stored is! Map) return;
    final edits = Map.of(stored)
      ..removeWhere((key, _) {
        try {
          final pair = jsonDecode(key.toString());
          return pair is! List ||
              pair.length != 2 ||
              !pair.every(songs.contains);
        } catch (_) {
          return true;
        }
      });
    if (edits.length == stored.length) return;
    if (edits.isEmpty) {
      all.remove(playlist);
    } else {
      all[playlist] = edits;
    }
    await Hive.box('settings').put(storageKey, all);
    changes.value++;
  }
}
