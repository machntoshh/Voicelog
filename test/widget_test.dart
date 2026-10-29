import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicelog/data/library_store.dart';
import 'package:voicelog/main.dart';
import 'package:voicelog/models.dart';
import 'package:voicelog/services/recorder_controller.dart';
import 'package:voicelog/services/transcription_service.dart';
import 'package:voicelog/ui/recording_tile.dart';

void main() {
  LibraryStore sample() {
    final s = LibraryStore(Directory.systemTemp);
    final work = Folder(id: 'f1', name: 'Trabalho', createdAt: DateTime(2026, 10, 1));
    s.folders.add(work);
    s.recordings.addAll([
      Recording(
        id: 'r1',
        name: 'Reunião de pauta',
        createdAt: DateTime(2026, 10, 29, 9, 5),
        fileName: 'r1.aac',
        duration: const Duration(minutes: 3, seconds: 12),
        folderId: 'f1',
      ),
      Recording(
        id: 'r2',
        name: 'Ideia solta',
        createdAt: DateTime(2026, 10, 29, 10, 35),
        fileName: 'r2.aac',
        duration: const Duration(seconds: 42),
        transcriptStatus: TranscriptStatus.done,
        transcript: const [
          TranscriptSegment(Duration.zero, 'Lembrar de comprar café.'),
          TranscriptSegment(Duration(seconds: 12), 'Ligar para o fornecedor amanhã cedo.'),
        ],
      ),
    ]);
    return s;
  }

  Future<void> pump(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = sample();
    await tester.pumpWidget(VoiceLogApp(
        store: store, recorder: RecorderController(store), transcriber: TranscriptionService(store)));
  }

  testWidgets('desktop: sidebar with folders, recent list and record button', (tester) async {
    await pump(tester, const Size(1200, 800));
    expect(find.text('PASTAS'), findsOneWidget);
    expect(find.text('Trabalho'), findsWidgets);
    expect(find.text('Sem pasta'), findsWidgets);
    expect(find.text('Reunião de pauta'), findsOneWidget);
    expect(find.text('29/10/2026 · 09:05 · 03:12'), findsOneWidget);
    expect(find.byTooltip('Gravar'), findsOneWidget);
  });

  testWidgets('phone: folder strip and search by accent-free text', (tester) async {
    await pump(tester, const Size(400, 800));
    expect(find.text('PASTAS'), findsNothing);
    expect(find.text('Trabalho'), findsWidgets);

    await tester.enterText(find.byType(TextField), 'reuniao');
    await tester.pump();
    expect(find.text('Reunião de pauta'), findsOneWidget);
    expect(find.text('Ideia solta'), findsNothing);
  });

  testWidgets('selecting a folder shows only its recordings', (tester) async {
    await pump(tester, const Size(1200, 800));
    await tester.tap(find.text('Sem pasta').first);
    await tester.pump();
    expect(find.text('Ideia solta'), findsOneWidget);
    expect(find.text('Reunião de pauta'), findsNothing);
  });

  testWidgets('search finds spoken words and shows the passage', (tester) async {
    await pump(tester, const Size(400, 800));
    await tester.enterText(find.byType(TextField), 'fornecedor');
    await tester.pump();
    expect(find.text('Ideia solta'), findsOneWidget);
    expect(find.text('Reunião de pauta'), findsNothing);
    final passage = find.descendant(
        of: find.byType(RecordingTile), matching: find.textContaining('fornecedor', findRichText: true));
    expect(passage, findsOneWidget);
  });

  testWidgets('third-party licenses open from the transcription settings, in Portuguese', (tester) async {
    await pump(tester, const Size(1200, 800));
    await tester.tap(find.byTooltip('Transcrição'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Licenças de terceiros'));
    await tester.pumpAndSettle();
    expect(find.text('Licenças'), findsWidgets);
    expect(find.text('VoiceLog'), findsWidgets);
  });
}
