import 'dart:math';
import 'dart:typed_data';

/// Pitch-class profiles (major / minor), correlated against a windowed
/// chromagram. This is an estimate; ambiguous/percussive audio has no key.
({int? key, double confidence}) detectMixKey(Int16List samples, int rate) {
  const n = 2048;
  if (samples.length < n || rate <= 0) return (key: null, confidence: 0);
  final chroma = List<double>.filled(12, 0);
  final frames = min(48, samples.length ~/ n);
  final window = List.generate(n, (i) => 0.5 - 0.5 * cos(2 * pi * i / (n - 1)));
  for (var frame = 0; frame < frames; frame++) {
    final start = frame * (samples.length - n) ~/ max(1, frames - 1);
    for (var midi = 48; midi <= 83; midi++) {
      final frequency = 440 * pow(2, (midi - 69) / 12);
      if (frequency >= rate / 2) continue;
      final coefficient = 2 * cos(2 * pi * frequency / rate);
      var a = 0.0, b = 0.0;
      for (var i = 0; i < n; i++) {
        final v = samples[start + i] / 32768 * window[i] + coefficient * a - b;
        b = a;
        a = v;
      }
      final power = max(0, a * a + b * b - coefficient * a * b);
      chroma[midi % 12] += sqrt(power);
    }
  }
  const profiles = [
    [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88],
    [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17],
  ];
  final mean = chroma.reduce((a, b) => a + b) / 12;
  final variance = chroma.fold<double>(0, (s, x) => s + pow(x - mean, 2));
  if (variance < 0.001) return (key: null, confidence: 0);
  var best = -1.0, second = -1.0, key = 0;
  for (var mode = 0; mode < 2; mode++) {
    final profile = profiles[mode];
    final pm = profile.reduce((a, b) => a + b) / 12;
    final pv = profile.fold<double>(0, (s, x) => s + pow(x - pm, 2));
    for (var root = 0; root < 12; root++) {
      var dot = 0.0;
      for (var i = 0; i < 12; i++) {
        dot += (chroma[(i + root) % 12] - mean) * (profile[i] - pm);
      }
      final score = dot / sqrt(variance * pv);
      if (score > best) {
        second = best;
        best = score;
        key = root + mode * 12;
      } else if (score > second) {
        second = score;
      }
    }
  }
  final confidence = (best * ((best - second) / 0.12).clamp(0.0, 1.0)).clamp(
    0.0,
    1.0,
  );
  return (
    key: best >= 0.6 && confidence >= 0.25 ? key : null,
    confidence: confidence,
  );
}

const _major = [8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6, 1];
const _minor = [5, 12, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10];
String camelotKey(int key) =>
    '${(key < 12 ? _major : _minor)[key % 12]}${key < 12 ? 'B' : 'A'}';
double harmonicDistance(int? a, int? b) {
  if (a == null || b == null) return 1;
  final x = (a < 12 ? _major : _minor)[a % 12];
  final y = (b < 12 ? _major : _minor)[b % 12];
  final d = (x - y).abs();
  return min(d, 12 - d).toDouble() +
      (a ~/ 12 == b ~/ 12
          ? 0
          : x == y
          ? 0.5
          : 1);
}

double tempoRatio(double outgoing, double incoming) {
  if (outgoing <= 0 || incoming <= 0) return 1;
  var ratio = outgoing / incoming;
  while (ratio > 1.5) {
    ratio /= 2;
  }
  while (ratio < 0.75) {
    ratio *= 2;
  }
  return ratio.clamp(0.94, 1.06);
}
