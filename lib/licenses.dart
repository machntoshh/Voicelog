import 'package:flutter/foundation.dart';

/// Adds notices for components that don't come from a Dart package, so
/// Flutter's license page lists them next to the packages it already knows.
///
/// - ONNX Runtime ships inside the app with sherpa-onnx's native libraries.
/// - Whisper and Silero VAD models are downloaded on demand, not bundled,
///   but are credited because the app is built around them.
void registerThirdPartyLicenses() {
  LicenseRegistry.addLicense(() => Stream.fromIterable([
        LicenseEntryWithLineBreaks(['ONNX Runtime'], _mit('Copyright (c) Microsoft Corporation')),
        LicenseEntryWithLineBreaks(['Whisper (modelos de transcrição)'], _mit('Copyright (c) 2022 OpenAI')),
        LicenseEntryWithLineBreaks(['Silero VAD (detector de voz)'], _mit('Copyright (c) 2020-present Silero Team')),
      ]));
}

String _mit(String copyright) => '''MIT License

$copyright

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.''';
