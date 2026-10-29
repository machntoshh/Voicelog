import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicelog/data/library_store.dart';
import 'package:voicelog/models.dart';

import 'helpers.dart';

void main() {
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('voicelog_test'));
  tearDown(() async => root.delete(recursive: true));

  Future<LibraryStore> open() async {
    final s = LibraryStore(root);
    await s.load();
    return s;
  }

  /// Simulates a finished recording with real ADTS audio on disk.
  Future<Recording> record(LibraryStore s, {int frames = 50}) async {
    final r = await s.beginRecording(DateTime(2026, 10, 29, 10, 35));
    await s.audioFile(r).writeAsBytes(adtsFrames(frames));
    await s.finishRecording(r, await s.measure(r), [10, 50, 90]);
    return r;
  }

  int audioFileCount() => Directory('${root.path}/audio').listSync().length;

  test('folders and recordings survive closing and reopening', () async {
    final s = await open();
    final f = await s.createFolder('Trabalho');
    final r = await record(s);
    await s.updateRecording(r, name: 'Reunião semanal', folderId: f.id);

    final reopened = await open();
    expect(reopened.folders.single.name, 'Trabalho');
    final again = reopened.recordings.single;
    expect(again.name, 'Reunião semanal');
    expect(again.folderId, f.id);
    expect(again.status, RecordingStatus.ready);
    expect(again.duration.inMilliseconds, r.duration.inMilliseconds);
    expect(again.waveform, [10, 50, 90]);
    expect(reopened.recoveredOnLoad, 0);
  });

  test('moving changes only the folder, never copies the audio', () async {
    final s = await open();
    final a = await s.createFolder('A');
    final b = await s.createFolder('B');
    final r = await record(s);
    final path = s.audioFile(r).path;

    await s.moveRecording(r, a.id);
    await s.moveRecording(r, b.id);
    await s.moveRecording(r, null);

    expect(audioFileCount(), 1);
    expect(s.audioFile(r).path, path);
    expect(s.inFolder(null), [r]);
    expect(s.countIn(a.id), 0);
  });

  test('a recording interrupted by a crash is recovered on next launch', () async {
    final s = await open();
    final r = await s.beginRecording(DateTime.now());
    // Process dies mid-write: complete frames plus half a frame.
    final full = adtsFrames(40);
    await s.audioFile(r).writeAsBytes([...full, ...adtsFrames(1).sublist(0, 30)]);

    final reopened = await open();
    final rec = reopened.recordings.single;
    expect(reopened.recoveredOnLoad, 1);
    expect(rec.status, RecordingStatus.ready);
    expect(rec.recovered, isTrue);
    expect(rec.folderId, isNull);
    expect(rec.duration.inMilliseconds, (40 * 1024 * 1000 / 44100).floor());
    expect(await reopened.audioFile(rec).length(), full.length);
  });

  test('an interrupted recording with no audio is dropped', () async {
    final s = await open();
    await s.beginRecording(DateTime.now());
    final reopened = await open();
    expect(reopened.recordings, isEmpty);
  });

  test('audio files missing from the metadata are adopted, not lost', () async {
    await open();
    await File('${root.path}/audio/orphan.aac').writeAsBytes(adtsFrames(20));
    final s = await open();
    expect(s.recordings.single.fileName, 'orphan.aac');
    expect(s.recordings.single.recovered, isTrue);
  });

  test('deleting a folder can keep its recordings in Sem pasta', () async {
    final s = await open();
    final f = await s.createFolder('Ideias');
    final r = await record(s);
    await s.moveRecording(r, f.id);

    await s.deleteFolder(f, deleteRecordings: false);
    expect(s.folders, isEmpty);
    expect(r.folderId, isNull);
    expect(audioFileCount(), 1);
  });

  test('deleting a folder with its recordings removes the audio', () async {
    final s = await open();
    final f = await s.createFolder('Ideias');
    final r = await record(s);
    await s.moveRecording(r, f.id);

    await s.deleteFolder(f, deleteRecordings: true);
    expect(s.recordings, isEmpty);
    expect(audioFileCount(), 0);
  });

  test('a corrupted library file falls back to the backup', () async {
    final s = await open();
    await s.createFolder('Primeira');
    await s.createFolder('Segunda'); // backup now holds "Primeira"
    await File('${root.path}/library.json').writeAsString('{"folders": [tru');

    final reopened = await open();
    expect(reopened.folders.map((f) => f.name), ['Primeira']);
  });

  test('search matches name, folder and date, ignoring accents', () async {
    final s = await open();
    final f = await s.createFolder('Estudos');
    final a = await record(s);
    final b = await record(s);
    await s.updateRecording(a, name: 'Reunião com equipe', folderId: null);
    await s.updateRecording(b, name: 'Leitura', folderId: f.id);

    List<Recording> found(String q) => [for (final h in s.search(q)) h.recording];
    expect(found('reuniao'), [a]);
    expect(found('estudos'), [b]);
    expect(found('29/10/2026').length, 2);
    expect(found('reuniao estudos'), isEmpty);
  });

  test('search finds spoken words with a snippet and the time they are said', () async {
    final s = await open();
    final r = await record(s);
    await s.saveTranscript(r, const [
      TranscriptSegment(Duration.zero, 'Bom dia, começando o registro.'),
      TranscriptSegment(Duration(seconds: 14), 'Precisamos marcar a reunião com o cliente.'),
    ]);

    final hit = s.search('reuniao cliente').single;
    expect(hit.recording, r);
    expect(hit.at, const Duration(seconds: 14));
    final (start, end) = hit.match!;
    expect(hit.snippet!.substring(start, end), 'reunião');
    expect(s.search('orcamento'), isEmpty);

    final reopened = await open();
    expect(reopened.recordings.single.transcriptText, contains('reunião com o cliente'));
    expect(reopened.recordings.single.transcriptStatus, TranscriptStatus.done);
  });

  test('recordings in progress are hidden from lists', () async {
    final s = await open();
    await s.beginRecording(DateTime.now());
    expect(s.allReady, isEmpty);
    expect(s.countIn(null), 0);
  });

  test('a transcription cut off by closing the app is marked as failed', () async {
    final s = await open();
    final r = await record(s);
    await s.setTranscriptStatus(r, TranscriptStatus.running);

    final reopened = await open();
    final again = reopened.recordings.single;
    expect(again.transcriptStatus, TranscriptStatus.failed);
    expect(again.transcriptError, isNotNull);
    expect(await reopened.audioFile(again).exists(), isTrue);
  });

  test('transcription settings persist', () async {
    final s = await open();
    s.transcription
      ..modelId = 'whisper-small'
      ..autoTranscribe = true;
    await s.saveTranscriptionSettings();

    final reopened = await open();
    expect(reopened.transcription.modelId, 'whisper-small');
    expect(reopened.transcription.autoTranscribe, isTrue);
  });
}
