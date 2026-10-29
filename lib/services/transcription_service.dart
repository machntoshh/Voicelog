import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:audio_decoder/audio_decoder.dart';
import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../data/library_store.dart';
import '../models.dart';
import 'speech_models.dart';

const _sampleRate = 16000;

/// Transcribes recordings on the device, one at a time, with Whisper.
///
/// The audio is decoded to 16 kHz PCM, split into speech segments by a
/// voice-activity detector, and each segment is transcribed in a background
/// isolate so the UI stays responsive. Nothing is sent over the network.
class TranscriptionService extends ChangeNotifier {
  TranscriptionService(this.store) : downloader = ModelDownloader(store.modelsDir);

  final LibraryStore store;
  final ModelDownloader downloader;

  final List<Recording> _queue = [];
  Recording? current;

  /// Progress of [current]: null while decoding, then 0–1.
  double? progress;

  WhisperModel? get model => whisperModelById(store.settings.modelId);

  /// Re-queues work left pending by a previous session.
  void resumePending() {
    for (final r in store.allReady) {
      if (r.transcriptStatus == TranscriptStatus.pending) _queue.add(r);
    }
    _pump();
  }

  /// Queues [r]. Returns false when no model is installed yet.
  Future<bool> request(Recording r) async {
    final m = model;
    if (m == null || !await downloader.isInstalled(m)) return false;
    if (r == current || _queue.contains(r)) return true;
    await store.setTranscriptStatus(r, TranscriptStatus.pending);
    _queue.add(r);
    _pump();
    return true;
  }

  /// Called for each newly saved recording.
  void onRecordingSaved(Recording r) {
    if (store.settings.autoTranscribe) request(r);
  }

  Future<void> useModel(WhisperModel m) async {
    store.settings.modelId = m.id;
    await store.saveSettings();
    notifyListeners();
  }

  Future<void> removeModel() async {
    final m = model;
    if (m != null) await downloader.delete(m);
    store.settings.modelId = null;
    await store.saveSettings();
    notifyListeners();
  }

  Future<void> setAutoTranscribe(bool on) async {
    store.settings.autoTranscribe = on;
    await store.saveSettings();
    notifyListeners();
  }

  Future<void> _pump() async {
    if (current != null || _queue.isEmpty) return;
    final r = _queue.removeAt(0);
    if (!store.recordings.contains(r)) return _pump();
    current = r;
    progress = null;
    notifyListeners();
    await store.setTranscriptStatus(r, TranscriptStatus.running);
    final tmp = Directory('${store.root.path}${Platform.pathSeparator}tmp');
    final wav = File('${tmp.path}${Platform.pathSeparator}${r.id}.wav');
    try {
      final m = model;
      if (m == null || !await downloader.isInstalled(m)) {
        throw const _UserFacing('O modelo de transcrição não está instalado.');
      }
      await tmp.create(recursive: true);
      try {
        await AudioDecoder.convertToWav(store.audioFile(r).path, wav.path,
            sampleRate: _sampleRate, channels: 1, bitDepth: 16);
      } on Object {
        throw const _UserFacing('Não foi possível ler o áudio desta gravação.');
      }
      final segments = await _runWorker(_Job(
        wav: wav.path,
        encoder: downloader.fileIn(m, m.encoder).path,
        decoder: downloader.fileIn(m, m.decoder).path,
        tokens: downloader.fileIn(m, m.tokens).path,
        vad: downloader.vadFile(m).path,
        threads: max(1, min(4, Platform.numberOfProcessors - 1)),
      ));
      if (store.recordings.contains(r)) await store.saveTranscript(r, segments);
    } on _UserFacing catch (e) {
      await store.setTranscriptStatus(r, TranscriptStatus.failed, error: e.message);
    } on Object catch (e) {
      await store.setTranscriptStatus(r, TranscriptStatus.failed, error: 'Falha na transcrição: $e');
    } finally {
      if (await wav.exists()) await wav.delete();
      current = null;
      progress = null;
      notifyListeners();
      unawaited(_pump());
    }
  }

  Future<List<TranscriptSegment>> _runWorker(_Job job) async {
    final port = ReceivePort();
    final errors = ReceivePort();
    final done = Completer<List<TranscriptSegment>>();
    port.listen((msg) {
      switch (msg) {
        case double p:
          progress = p;
          notifyListeners();
        case List<Object?> segments:
          done.complete([
            for (final s in segments.cast<(int, String)>()) TranscriptSegment(Duration(milliseconds: s.$1), s.$2),
          ]);
        case String error:
          done.completeError(_UserFacing(error));
      }
    });
    errors.listen((e) {
      if (!done.isCompleted) done.completeError(_UserFacing('Falha na transcrição: ${(e as List).first}'));
    });
    await Isolate.spawn(_transcribe, (job, port.sendPort), onError: errors.sendPort);
    try {
      return await done.future;
    } finally {
      port.close();
      errors.close();
    }
  }
}

class _UserFacing implements Exception {
  const _UserFacing(this.message);
  final String message;
}

class _Job {
  const _Job({
    required this.wav,
    required this.encoder,
    required this.decoder,
    required this.tokens,
    required this.vad,
    required this.threads,
  });

  final String wav;
  final String encoder;
  final String decoder;
  final String tokens;
  final String vad;
  final int threads;
}

/// Isolate entry point. Sends progress as doubles, then either the segments
/// as `(startMs, text)` records or an error message string.
Future<void> _transcribe((_Job, SendPort) args) async {
  final (job, out) = args;
  sherpa.VoiceActivityDetector? vad;
  sherpa.OfflineRecognizer? recognizer;
  RandomAccessFile? file;
  try {
    sherpa.initBindings();
    vad = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(model: job.vad, minSilenceDuration: 0.5, maxSpeechDuration: 20),
        sampleRate: _sampleRate,
        debug: false,
      ),
      bufferSizeInSeconds: 60,
    );
    recognizer = sherpa.OfflineRecognizer(sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: job.encoder,
          decoder: job.decoder,
          language: 'pt',
          task: 'transcribe',
        ),
        tokens: job.tokens,
        numThreads: job.threads,
        debug: false,
      ),
    ));

    final segments = <(int, String)>[];
    void drain() {
      while (!vad!.isEmpty()) {
        final seg = vad.front();
        final stream = recognizer!.createStream();
        stream.acceptWaveform(samples: seg.samples, sampleRate: _sampleRate);
        recognizer.decode(stream);
        final text = recognizer.getResult(stream).text.trim();
        stream.free();
        if (text.isNotEmpty) segments.add((seg.start * 1000 ~/ _sampleRate, text));
        vad.pop();
      }
    }

    file = await File(job.wav).open();
    final (offset, length) = await readWavPcmRange(file);
    await file.setPosition(offset);
    const window = 512;
    const chunkBytes = window * 2 * 64;
    var read = 0;
    var carry = Float32List(0);
    while (read < length) {
      final bytes = await file.read(min(chunkBytes, length - read));
      if (bytes.isEmpty) break;
      read += bytes.length;
      final samples = Float32List.fromList([...carry, ...pcm16ToFloat(bytes)]);
      var i = 0;
      for (; i + window <= samples.length; i += window) {
        vad.acceptWaveform(Float32List.sublistView(samples, i, i + window));
        drain();
      }
      carry = Float32List.fromList(samples.sublist(i));
      out.send(read / length);
    }
    vad.flush();
    drain();
    out.send(segments);
  } on Object catch (e) {
    out.send('$e');
  } finally {
    await file?.close();
    recognizer?.free();
    vad?.free();
  }
}

/// Converts little-endian 16-bit PCM to floats in [-1, 1].
Float32List pcm16ToFloat(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final out = Float32List(bytes.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

/// Finds the PCM payload of a 16 kHz mono 16-bit WAV file and returns its
/// byte offset and length.
Future<(int, int)> readWavPcmRange(RandomAccessFile f) async {
  final total = await f.length();
  await f.setPosition(0);
  final riff = await f.read(12);
  if (riff.length < 12 || String.fromCharCodes(riff.sublist(0, 4)) != 'RIFF') {
    throw const FormatException('Áudio decodificado inválido.');
  }
  var pos = 12;
  var formatOk = false;
  while (pos + 8 <= total) {
    await f.setPosition(pos);
    final header = ByteData.sublistView(await f.read(8));
    final id = String.fromCharCodes(Uint8List.sublistView(header, 0, 4));
    final size = header.getUint32(4, Endian.little);
    if (id == 'fmt ') {
      final fmt = ByteData.sublistView(await f.read(16));
      const pcm = 1, extensible = 0xFFFE;
      final tag = fmt.getUint16(0, Endian.little);
      formatOk = (tag == pcm || tag == extensible) &&
          fmt.getUint16(2, Endian.little) == 1 &&
          fmt.getUint32(4, Endian.little) == _sampleRate &&
          fmt.getUint16(14, Endian.little) == 16;
    } else if (id == 'data') {
      if (!formatOk) throw const FormatException('Formato de áudio decodificado inesperado.');
      final start = pos + 8;
      return (start, min(size, total - start));
    }
    pos += 8 + size + (size & 1);
  }
  throw const FormatException('Áudio decodificado sem dados.');
}
