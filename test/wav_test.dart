import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicelog/services/transcription_service.dart';

Uint8List wav({int rate = 16000, int bits = 16, int channels = 1, List<int> samples = const [0, 16384, -32768]}) {
  final data = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(i * 2, samples[i], Endian.little);
  }
  final h = ByteData(44);
  void tag(int at, String s) => s.codeUnits.asMap().forEach((i, c) => h.setUint8(at + i, c));
  tag(0, 'RIFF');
  h.setUint32(4, 36 + data.lengthInBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  h.setUint32(16, 16, Endian.little);
  h.setUint16(20, 1, Endian.little);
  h.setUint16(22, channels, Endian.little);
  h.setUint32(24, rate, Endian.little);
  h.setUint32(28, rate * channels * bits ~/ 8, Endian.little);
  h.setUint16(32, channels * bits ~/ 8, Endian.little);
  h.setUint16(34, bits, Endian.little);
  tag(36, 'data');
  h.setUint32(40, data.lengthInBytes, Endian.little);
  return Uint8List.fromList([...h.buffer.asUint8List(), ...data.buffer.asUint8List()]);
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('voicelog_wav'));
  tearDown(() async => dir.delete(recursive: true));

  Future<(int, int)> range(Uint8List bytes) async {
    final f = File('${dir.path}/a.wav');
    await f.writeAsBytes(bytes);
    final raf = await f.open();
    try {
      return await readWavPcmRange(raf);
    } finally {
      await raf.close();
    }
  }

  test('finds the PCM payload of a 16 kHz mono 16-bit file', () async {
    expect(await range(wav()), (44, 6));
  });

  test('rejects audio in another format', () async {
    expect(range(wav(rate: 44100)), throwsFormatException);
    expect(range(wav(channels: 2)), throwsFormatException);
  });

  test('converts 16-bit samples to floats', () {
    final bytes = Uint8List.sublistView(wav(), 44);
    expect(pcm16ToFloat(bytes), [0.0, 0.5, -1.0]);
  });
}
