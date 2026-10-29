import 'package:flutter/widgets.dart';

import '../data/library_store.dart';
import '../services/recorder_controller.dart';
import '../services/transcription_service.dart';

/// Gives widgets access to the app-wide store, recorder and transcriber.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.store, required this.recorder, required this.transcriber, required super.child});

  final LibraryStore store;
  final RecorderController recorder;
  final TranscriptionService transcriber;

  static AppScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope old) => store != old.store || recorder != old.recorder || transcriber != old.transcriber;
}
