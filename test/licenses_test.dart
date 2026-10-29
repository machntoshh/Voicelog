import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicelog/licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('credits the native runtime and the speech models', () async {
    registerThirdPartyLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final packages = entries.expand((e) => e.packages).toSet();
    expect(packages, containsAll(['ONNX Runtime', 'Whisper (modelos de transcrição)', 'Silero VAD (detector de voz)']));
    final whisper = entries.firstWhere((e) => e.packages.contains('Whisper (modelos de transcrição)'));
    final text = whisper.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('Copyright (c) 2022 OpenAI'));
    expect(text, contains('MIT License'));
  });
}
