import 'dart:math';
import 'dart:typed_data';

Uint8List silentWav({int size = 32000}) {
  final bytes = ByteData(44 + size);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  text(8, 'WAVE');
  text(12, 'fmt ');
  text(36, 'data');
  bytes
    ..setUint32(4, 36 + size, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 8000, Endian.little)
    ..setUint32(28, 16000, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(40, size, Endian.little);
  return bytes.buffer.asUint8List();
}

/// Two seconds of a bass hit every half second over a faint high tone, at
/// 22.05 kHz mono, for checks that follow beats.
Uint8List beatsWav({int seconds = 2}) => _monoWav(22050, seconds, (t) {
  final hit = exp(-(t % 0.5) * 12) * sin(2 * pi * 60 * t);
  return 0.8 * hit + 0.05 * sin(2 * pi * 3000 * t);
});

/// A steady mono sine of [hz] and [amplitude] (0 to 1) at [rate], for checks
/// that measure how a filter changes the level of one frequency.
Uint8List toneWav({
  double hz = 60,
  double amplitude = 0.1,
  int rate = 44100,
  int seconds = 2,
}) => _monoWav(rate, seconds, (t) => amplitude * sin(2 * pi * hz * t));

Uint8List _monoWav(int rate, int seconds, double Function(double t) sample) {
  final samples = rate * seconds;
  final bytes = ByteData(44 + samples * 2);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  text(8, 'WAVE');
  text(12, 'fmt ');
  text(36, 'data');
  bytes
    ..setUint32(4, 36 + samples * 2, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    bytes.setInt16(
      44 + i * 2,
      (sample(i / rate) * 32000).round(),
      Endian.little,
    );
  }
  return bytes.buffer.asUint8List();
}
