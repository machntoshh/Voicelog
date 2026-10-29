import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicelog/data/adts.dart';

import 'helpers.dart';

void main() {
  test('computes exact duration from frame headers', () {
    final scan = scanAdts(adtsFrames(431));
    expect(scan.duration.inMilliseconds, (431 * 1024 * 1000 / 44100).floor());
    expect(scan.validLength, 431 * 107);
  });

  test('stops at a partial trailing frame left by a crash', () {
    final full = adtsFrames(10);
    final cut = Uint8List.fromList([...full, ...adtsFrames(1).sublist(0, 50)]);
    final scan = scanAdts(cut);
    expect(scan.validLength, full.length);
    expect(scan.duration, scanAdts(full).duration);
  });

  test('returns zero for data that is not ADTS', () {
    final scan = scanAdts(Uint8List.fromList(List.filled(64, 7)));
    expect(scan.duration, Duration.zero);
    expect(scan.validLength, 0);
  });
}
