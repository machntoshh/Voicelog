import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../format.dart';
import '../models.dart';
import 'theme.dart';

void showMessage(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(children: [
        Icon(error ? Icons.error_outline : Icons.check_circle_outline,
            size: 18, color: error ? VL.error : VL.success),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ]),
    ));
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String confirm = 'Salvar',
}) {
  final controller = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  return showDialog<String>(
    context: context,
    builder: (context) {
      void submit() {
        final v = controller.text.trim();
        if (v.isNotEmpty) Navigator.pop(context, v);
      }

      return AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (_) => submit(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: submit, child: Text(confirm)),
        ],
      );
    },
  );
}

Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String confirm = 'Excluir',
  bool destructive = true,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: VL.red, foregroundColor: VL.text) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Lets the user pick a destination. Returns `(id: null)` for "Sem pasta",
/// or null when cancelled.
Future<({String? id})?> pickFolder(BuildContext context, LibraryStore store, {String? current}) {
  return showDialog<({String? id})>(
    context: context,
    builder: (context) => SimpleDialog(
      title: const Text('Mover para pasta'),
      children: [
        _FolderOption(icon: Icons.inbox_outlined, label: 'Sem pasta', selected: current == null,
            onTap: () => Navigator.pop(context, (id: null))),
        for (final f in store.sortedFolders(SortMode.name))
          _FolderOption(icon: Icons.folder_outlined, label: f.name, selected: current == f.id,
              onTap: () => Navigator.pop(context, (id: f.id))),
        _FolderOption(
          icon: Icons.create_new_folder_outlined,
          label: 'Nova pasta…',
          onTap: () async {
            final name = await promptText(context, title: 'Nova pasta', hint: 'Nome da pasta', confirm: 'Criar');
            if (name == null || !context.mounted) return;
            final f = await store.createFolder(name);
            if (context.mounted) Navigator.pop(context, (id: f.id));
          },
        ),
      ],
    ),
  );
}

class _FolderOption extends StatelessWidget {
  const _FolderOption({required this.icon, required this.label, required this.onTap, this.selected = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => SimpleDialogOption(
        onPressed: onTap,
        child: Row(children: [
          Icon(icon, size: 20, color: VL.textDim),
          const SizedBox(width: 12),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
          if (selected) const Icon(Icons.check, size: 18, color: VL.success),
        ]),
      );
}

enum DeleteFolderChoice { moveToUnfiled, deleteRecordings }

Future<DeleteFolderChoice?> askDeleteFolder(BuildContext context, Folder folder, int count) {
  if (count == 0) {
    return confirmDestructive(context, title: 'Excluir pasta', message: 'Excluir a pasta "${folder.name}"?')
        .then((ok) => ok ? DeleteFolderChoice.moveToUnfiled : null);
  }
  return showDialog<DeleteFolderChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Excluir pasta'),
      content: Text('A pasta "${folder.name}" tem $count ${count == 1 ? 'gravação' : 'gravações'}. '
          'O que fazer com os áudios?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: VL.red),
          onPressed: () => Navigator.pop(context, DeleteFolderChoice.deleteRecordings),
          child: const Text('Excluir também'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, DeleteFolderChoice.moveToUnfiled),
          child: const Text('Mover para Sem pasta'),
        ),
      ],
    ),
  );
}

/// Shown right after a recording ends. The recording is already stored in
/// "Sem pasta"; this only names and files it. Returns whether it was saved
/// (false means the dialog was dismissed and the defaults were kept).
Future<bool> showSaveDialog(BuildContext context, LibraryStore store, Recording r) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => _SaveDialog(store: store, recording: r),
  );
  return saved ?? false;
}

class _SaveDialog extends StatefulWidget {
  const _SaveDialog({required this.store, required this.recording});

  final LibraryStore store;
  final Recording recording;

  @override
  State<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<_SaveDialog> {
  late final _name = TextEditingController(text: widget.recording.name);
  late String? _folderId = widget.recording.folderId;
  bool _saving = false;

  Future<void> _newFolder() async {
    final name = await promptText(context, title: 'Nova pasta', hint: 'Nome da pasta', confirm: 'Criar');
    if (name == null) return;
    final f = await widget.store.createFolder(name);
    setState(() => _folderId = f.id);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.store.updateRecording(widget.recording, name: _name.text, folderId: _folderId);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recording;
    final folders = widget.store.sortedFolders(SortMode.name);
    const meta = TextStyle(color: VL.textDim, fontFeatures: VL.tabular);
    return AlertDialog(
      title: const Text('Salvar gravação'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nome'),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.event_outlined, size: 16, color: VL.textFaint),
              const SizedBox(width: 6),
              Text('${formatDate(r.createdAt)}  ${formatTime(r.createdAt)}', style: meta),
              const Spacer(),
              const Icon(Icons.timer_outlined, size: 16, color: VL.textFaint),
              const SizedBox(width: 6),
              Text(formatDuration(r.duration), style: meta),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  key: ValueKey(_folderId),
                  initialValue: _folderId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Pasta'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Sem pasta')),
                    for (final f in folders)
                      DropdownMenuItem(value: f.id, child: Text(f.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _folderId = v),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Nova pasta',
                onPressed: _newFolder,
                icon: const Icon(Icons.create_new_folder_outlined),
              ),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Depois')),
        FilledButton(onPressed: _saving ? null : _save, child: const Text('Salvar')),
      ],
    );
  }
}
