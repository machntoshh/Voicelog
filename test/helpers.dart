import 'dart:typed_data';

/// Builds [frames] AAC-LC ADTS frames (mono, 44.1 kHz) with [payload] bytes each.
Uint8List adtsFrames(int frames, {int payload = 100}) {
  final len = payload + 7;
  final frame = [
    0xFF, 0xF1, // sync, MPEG-4, layer 0, no CRC
    (1 << 6) | (4 << 2), // AAC LC, 44100 Hz, channel config high bit 0
    (1 << 6) | ((len >> 11) & 0x03), // mono
    (len >> 3) & 0xFF,
    ((len & 0x07) << 5) | 0x1F,
    0xFC, // buffer fullness, 1 raw block
    ...List.filled(payload, 0x21),
  ];
  return Uint8List.fromList([for (var i = 0; i < frames; i++) ...frame]);
}
