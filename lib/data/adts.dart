import 'dart:typed_data';

const _sampleRates = [
  96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350,
];

/// Result of scanning an AAC/ADTS byte stream.
class AdtsScan {
  const AdtsScan(this.duration, this.validLength);

  final Duration duration;

  /// Length of the prefix made only of complete frames. A file cut off by a
  /// crash can be truncated to this length to drop the partial last frame.
  final int validLength;
}

/// Walks ADTS frame headers to compute the exact duration. Each ADTS frame is
/// self-contained, which is why recordings are stored in this format: a file
/// interrupted mid-write stays playable up to its last complete frame.
AdtsScan scanAdts(Uint8List b) {
  var i = 0;
  var samples = 0;
  int? sampleRate;
  while (i + 7 <= b.length) {
    // 12-bit sync word 0xFFF and layer 00.
    if (b[i] != 0xFF || (b[i + 1] & 0xF6) != 0xF0) break;
    final rateIndex = (b[i + 2] >> 2) & 0x0F;
    if (rateIndex >= _sampleRates.length) break;
    final frameLength = ((b[i + 3] & 0x03) << 11) | (b[i + 4] << 3) | (b[i + 5] >> 5);
    if (frameLength < 7 || i + frameLength > b.length) break;
    sampleRate ??= _sampleRates[rateIndex];
    samples += ((b[i + 6] & 0x03) + 1) * 1024;
    i += frameLength;
  }
  if (sampleRate == null) return const AdtsScan(Duration.zero, 0);
  return AdtsScan(Duration(microseconds: samples * 1000000 ~/ sampleRate), i);
}
