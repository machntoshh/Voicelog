import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'data/library_store.dart';
import 'services/recorder_controller.dart';
import 'services/transcription_service.dart';
import 'ui/app_scope.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final docs = await getApplicationDocumentsDirectory();
    final store = LibraryStore(Directory('${docs.path}${Platform.pathSeparator}VoiceLog'));
    await store.load();
    final transcriber = TranscriptionService(store)..resumePending();
    runApp(VoiceLogApp(store: store, recorder: RecorderController(store), transcriber: transcriber));
  } on Object catch (e) {
    runApp(_StartupError('$e'));
  }
}

class VoiceLogApp extends StatelessWidget {
  const VoiceLogApp({super.key, required this.store, required this.recorder, required this.transcriber});

  final LibraryStore store;
  final RecorderController recorder;
  final TranscriptionService transcriber;

  @override
  Widget build(BuildContext context) => AppScope(
        store: store,
        recorder: recorder,
        transcriber: transcriber,
        child: MaterialApp(
          title: 'VoiceLog',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: const HomePage(),
        ),
      );
}

class _StartupError extends StatelessWidget {
  const _StartupError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text('Não foi possível abrir o arquivo de gravações.\n\n$message', textAlign: TextAlign.center),
            ),
          ),
        ),
      );
}
