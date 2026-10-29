import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// A file fetched once and checked against a known size and SHA-256.
class ModelFile {
  const ModelFile(this.name, this.url, this.size, this.sha256);

  final String name;
  final String url;
  final int size;
  final String sha256;
}

class WhisperModel {
  const WhisperModel({required this.id, required this.label, required this.description, required this.files});

  final String id;
  final String label;
  final String description;
  final List<ModelFile> files;

  int get downloadSize => files.fold(0, (sum, f) => sum + f.size) + vadModel.size;

  String get encoder => files[0].name;
  String get decoder => files[1].name;
  String get tokens => files[2].name;
}

// Pinned to a revision so the hashes below stay valid.
const _hf = 'https://huggingface.co/csukuangfj';
const _tokensSha = 'b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126';

/// Silero voice-activity detector: splits audio into speech segments that
/// fit Whisper's 30-second window and skips silence.
const vadModel = ModelFile(
  'silero_vad.onnx',
  'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
  643854,
  '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
);

const whisperModels = [
  WhisperModel(
    id: 'whisper-small',
    label: 'Whisper small',
    description: 'Mais preciso em português. Mais lento em celulares simples.',
    files: [
      ModelFile('small-encoder.int8.onnx',
          '$_hf/sherpa-onnx-whisper-small/resolve/8f3c18b358db4d1f2fc1eae49d75cd20989e4309/small-encoder.int8.onnx',
          112442483, '4cbe7b22fa9026b843b60a68640c747de05bafb1a11b57edc0e66c232d9f33a9'),
      ModelFile('small-decoder.int8.onnx',
          '$_hf/sherpa-onnx-whisper-small/resolve/8f3c18b358db4d1f2fc1eae49d75cd20989e4309/small-decoder.int8.onnx',
          262226114, 'acad50b5c782696e91b55914cc5ab4f756f1532f76e22aa6fc615f39fb69a8ee'),
      ModelFile('small-tokens.txt',
          '$_hf/sherpa-onnx-whisper-small/resolve/8f3c18b358db4d1f2fc1eae49d75cd20989e4309/small-tokens.txt',
          816730, _tokensSha),
    ],
  ),
  WhisperModel(
    id: 'whisper-base',
    label: 'Whisper base',
    description: 'Cerca de 3× mais rápido e menor, porém erra mais.',
    files: [
      ModelFile('base-encoder.int8.onnx',
          '$_hf/sherpa-onnx-whisper-base/resolve/bb53ee204431c90d314c1cc08d28d23e5b7927cc/base-encoder.int8.onnx',
          29120534, '0b8fb1304b6109976038efff5ace81720e00386f3ff6b54ee8c75291ca0a1e11'),
      ModelFile('base-decoder.int8.onnx',
          '$_hf/sherpa-onnx-whisper-base/resolve/bb53ee204431c90d314c1cc08d28d23e5b7927cc/base-decoder.int8.onnx',
          130672026, '9759d217388a01b3a4c7c15533201067b48ae819c4daafc8624e64b9409dc02d'),
      ModelFile('base-tokens.txt',
          '$_hf/sherpa-onnx-whisper-base/resolve/bb53ee204431c90d314c1cc08d28d23e5b7927cc/base-tokens.txt',
          816730, _tokensSha),
    ],
  ),
];

WhisperModel? whisperModelById(String? id) => whisperModels.where((m) => m.id == id).firstOrNull;

/// Downloads and verifies speech models into `<library>/models/<model id>/`.
/// Only model files are downloaded; audio never leaves the device.
class ModelDownloader extends ChangeNotifier {
  ModelDownloader(this.modelsDir);

  final Directory modelsDir;

  /// Model currently downloading and its progress (0–1), if any.
  String? downloadingId;
  double progress = 0;

  Directory dirFor(WhisperModel m) => Directory('${modelsDir.path}${Platform.pathSeparator}${m.id}');
  File fileIn(WhisperModel m, String name) => File('${dirFor(m).path}${Platform.pathSeparator}$name');
  File vadFile(WhisperModel m) => fileIn(m, vadModel.name);

  /// Installed means every file is present with the expected size.
  Future<bool> isInstalled(WhisperModel m) async {
    for (final f in [...m.files, vadModel]) {
      final file = fileIn(m, f.name);
      if (!await file.exists() || await file.length() != f.size) return false;
    }
    return true;
  }

  Future<void> download(WhisperModel m) async {
    if (downloadingId != null) return;
    downloadingId = m.id;
    progress = 0;
    notifyListeners();
    final client = HttpClient();
    try {
      await dirFor(m).create(recursive: true);
      var done = 0;
      for (final f in [...m.files, vadModel]) {
        final target = fileIn(m, f.name);
        if (await target.exists() && await target.length() == f.size) {
          done += f.size;
          continue;
        }
        await _fetch(client, f, target, (received) {
          progress = (done + received) / m.downloadSize;
          notifyListeners();
        });
        done += f.size;
      }
    } finally {
      client.close(force: true);
      downloadingId = null;
      notifyListeners();
    }
  }

  Future<void> _fetch(HttpClient client, ModelFile f, File target, void Function(int) onProgress) async {
    final part = File('${target.path}.part');
    final request = await client.getUrl(Uri.parse(f.url));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode} ao baixar ${f.name}');
    }
    final sink = part.openWrite();
    var received = 0;
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(received);
      }
    } finally {
      await sink.close();
    }
    final path = part.path;
    final digest = await Isolate.run(() async => (await sha256.bind(File(path).openRead()).first).toString());
    if (received != f.size || digest != f.sha256) {
      await part.delete();
      throw const FormatException('O arquivo do modelo chegou corrompido. Tente novamente.');
    }
    await part.rename(target.path);
  }

  Future<void> delete(WhisperModel m) async {
    final dir = dirFor(m);
    if (await dir.exists()) await dir.delete(recursive: true);
    notifyListeners();
  }
}
