import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/library_store.dart';
import '../format.dart';
import '../models.dart';
import 'app_scope.dart';
import 'dialogs.dart';
import 'transcription_settings.dart';

/// Recording operations shared by the list menu and the player.
class RecordingActions {
  const RecordingActions(this.store);

  final LibraryStore store;

  Future<void> rename(BuildContext context, Recording r) async {
    final name = await promptText(context, title: 'Renomear gravação', initial: r.name);
    if (name != null) await store.renameRecording(r, name);
  }

  Future<void> move(BuildContext context, Recording r) async {
    final target = await pickFolder(context, store, current: r.folderId);
    if (target == null) return;
    await store.moveRecording(r, target.id);
    if (context.mounted) {
      showMessage(context, 'Movida para ${store.folderById(target.id)?.name ?? 'Sem pasta'}');
    }
  }

  Future<void> export(BuildContext context, Recording r) async {
    final source = store.audioFile(r);
    final fileName = '${safeFileName(r.name)}.aac';
    try {
      if (Platform.isAndroid) {
        await SharePlus.instance.share(ShareParams(
          files: [XFile(source.path, mimeType: 'audio/aac')],
          fileNameOverrides: [fileName],
          subject: r.name,
        ));
        return;
      }
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      var target = File('${dir.path}${Platform.pathSeparator}$fileName');
      for (var n = 2; await target.exists(); n++) {
        target = File('${dir.path}${Platform.pathSeparator}${safeFileName(r.name)} ($n).aac');
      }
      await source.copy(target.path);
      if (context.mounted) showMessage(context, 'Exportada para ${target.path}');
    } on Object catch (e) {
      if (context.mounted) showMessage(context, 'Não foi possível exportar: $e', error: true);
    }
  }

  /// Queues a transcription, first offering to set up a model if needed.
  Future<void> transcribe(BuildContext context, Recording r) async {
    final transcriber = AppScope.of(context).transcriber;
    if (await transcriber.request(r)) return;
    if (!context.mounted) return;
    await showTranscriptionSettings(context);
    if (!await transcriber.request(r) && context.mounted) {
      showMessage(context, 'Baixe um modelo de transcrição para continuar.', error: true);
    }
  }

  /// Returns whether the recording was deleted.
  Future<bool> delete(BuildContext context, Recording r) async {
    final ok = await confirmDestructive(
      context,
      title: 'Excluir gravação',
      message: 'Excluir "${r.name}" permanentemente? O áudio não poderá ser recuperado.',
    );
    if (!ok) return false;
    await store.deleteRecording(r);
    if (context.mounted) showMessage(context, 'Gravação excluída');
    return true;
  }
}
