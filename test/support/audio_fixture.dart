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
Uint8List beatsWav() {
  const rate = 22050;
  const samples = rate * 2;
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
    final t = i / rate;
    final hit = exp(-(t % 0.5) * 12) * sin(2 * pi * 60 * t);
    final value = 0.8 * hit + 0.05 * sin(2 * pi * 3000 * t);
    bytes.setInt16(44 + i * 2, (value * 32000).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}
