import 'package:flutter_test/flutter_test.dart';
import 'package:voicelog/format.dart';

void main() {
  final d = DateTime(2026, 10, 29, 10, 35, 7);

  test('suggests a name from date and time', () {
    expect(suggestedName(d), 'Registro_29-10-2026_10-35');
  });

  test('formats date, time and durations', () {
    expect(formatDate(d), '29/10/2026');
    expect(formatTime(d), '10:35');
    expect(formatDuration(const Duration(seconds: 65)), '01:05');
    expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
  });

  test('normalizes accents and case for search', () {
    expect(normalize('Reunião de Ação'), 'reuniao de acao');
  });

  test('makes file names safe', () {
    expect(safeFileName('a/b:c?'), 'a_b_c_');
    expect(safeFileName('  '), 'gravacao');
  });
}
