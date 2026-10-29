import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:voicelog/data/library_store.dart';
import 'package:voicelog/format.dart';
import 'package:voicelog/models.dart';
import 'package:voicelog/services/speech_models.dart';
import 'package:voicelog/services/transcription_service.dart';

/// Transcribes `fixtures/fala_ptbr.wav` (pt-BR speech) on the device with the
/// real Whisper model, downloading it once into a reusable cache folder.
///   flutter test integration_test/transcription_test.dart -d windows
///   ... --dart-define=MODEL=whisper-small
/// On Android, first copy the fixture into the app's files folder:
///   adb push integration_test/fixtures/fala_ptbr.wav /data/local/tmp/
///   adb shell run-as dev.voicelog.voicelog cp /data/local/tmp/fala_ptbr.wav app_flutter/
const _modelId = String.fromEnvironment('MODEL', defaultValue: 'whisper-base');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('transcribes Portuguese speech and finds it by spoken words', (tester) async {
    await tester.runAsync(() async {
      final docs = await getApplicationDocumentsDirectory();
      var fixture = File('${docs.path}/fala_ptbr.wav');
      if (!await fixture.exists()) fixture = File('integration_test/fixtures/fala_ptbr.wav');
      expect(await fixture.exists(), isTrue, reason: 'fixture missing');

      // Models persist between runs; the library itself starts empty.
      final root = Directory('${Directory.systemTemp.path}/voicelog_it_transcription');
      for (final name in ['library.json', 'library.json.bak', 'audio']) {
        final e = File('${root.path}/$name');
        if (await e.exists()) await e.delete();
        final d = Directory('${root.path}/$name');
        if (await d.exists()) await d.delete(recursive: true);
      }
      final store = LibraryStore(root);
      await store.load();
      await fixture.copy('${store.audioDir.path}/fala.wav');
      final r = Recording(
        id: 'fala',
        name: 'Fala de teste',
        createdAt: DateTime.now(),
        fileName: 'fala.wav',
        duration: const Duration(seconds: 16),
      );
      store.recordings.add(r);

      final service = TranscriptionService(store);
      final model = whisperModelById(_modelId)!;
      if (!await service.downloader.isInstalled(model)) await service.downloader.download(model);
      await service.useModel(model);

      final clock = Stopwatch()..start();
      expect(await service.request(r), isTrue);
      while (r.transcriptStatus == TranscriptStatus.pending || r.transcriptStatus == TranscriptStatus.running) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      clock.stop();
      // ignore: avoid_print
      print('[$_modelId] ${clock.elapsed.inMilliseconds} ms: ${r.transcript.map((s) => '${formatDuration(s.start)} ${s.text}').join(' | ')}');

      expect(r.transcriptError, isNull);
      expect(r.transcriptStatus, TranscriptStatus.done);
      expect(r.transcript.length, greaterThanOrEqualTo(2), reason: 'two sentences split by a pause');
      final text = normalize(r.transcriptText);
      for (final word in ['reuniao', 'fornecedor', 'proposta']) {
        expect(text, contains(word));
      }
      final hit = store.search('fornecedor').single;
      expect(hit.snippet, isNotNull);
      expect(hit.at, lessThan(const Duration(seconds: 4)));

      final second = r.transcript.firstWhere((s) => normalize(s.text).contains('proposta'));
      expect(second.start, greaterThan(const Duration(seconds: 4)));

      final reopened = LibraryStore(root);
      await reopened.load();
      expect(reopened.recordings.single.transcriptText, r.transcriptText);
    });
  }, timeout: const Timeout(Duration(minutes: 20)));
}
