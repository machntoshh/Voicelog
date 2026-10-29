import 'dart:io';

import 'package:flutter/material.dart';

import '../services/speech_models.dart';
import '../services/transcription_service.dart';
import 'app_scope.dart';
import 'dialogs.dart';
import 'theme.dart';

String _megabytes(int bytes) => '${(bytes / 1e6).round()} MB';

/// Model choice, download and automatic transcription switch.
Future<void> showTranscriptionSettings(BuildContext context) => showDialog<void>(
      context: context,
      builder: (_) => const _TranscriptionSettings(),
    );

class _TranscriptionSettings extends StatefulWidget {
  const _TranscriptionSettings();

  @override
  State<_TranscriptionSettings> createState() => _TranscriptionSettingsState();
}

class _TranscriptionSettingsState extends State<_TranscriptionSettings> {
  final Map<String, bool> _installed = {};
  String? _error;

  TranscriptionService get _service => AppScope.of(context).transcriber;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  Future<void> _refresh() async {
    for (final m in whisperModels) {
      _installed[m.id] = await _service.downloader.isInstalled(m);
    }
    if (mounted) setState(() {});
  }

  Future<void> _download(WhisperModel m) async {
    final ok = await confirmDestructive(
      context,
      title: 'Baixar ${m.label}?',
      message: 'Serão baixados ${_megabytes(m.downloadSize)} do Hugging Face e do GitHub, '
          'só uma vez. Use Wi-Fi se tiver franquia de dados.\n\n'
          'Apenas o modelo é baixado: seus áudios continuam no dispositivo e '
          'a transcrição roda sem internet.',
      confirm: 'Baixar',
      destructive: false,
    );
    if (!ok || !mounted) return;
    setState(() => _error = null);
    try {
      await _service.downloader.download(m);
      await _service.useModel(m);
      if (mounted) showMessage(context, '${m.label} pronto para transcrever.');
    } on SocketException {
      if (mounted) setState(() => _error = 'Sem conexão com a internet. Tente novamente quando estiver on-line.');
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'O download falhou: $e');
    }
    await _refresh();
  }

  Future<void> _remove(WhisperModel m) async {
    final ok = await confirmDestructive(
      context,
      title: 'Remover ${m.label}?',
      message: 'Libera ${_megabytes(m.downloadSize)}. As transcrições já feitas continuam salvas.',
      confirm: 'Remover',
    );
    if (!ok) return;
    if (_service.model?.id == m.id) {
      await _service.removeModel();
    } else {
      await _service.downloader.delete(m);
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_service, _service.downloader]),
      builder: (context, _) {
        final active = _service.model?.id;
        final settings = _service.store.settings;
        return AlertDialog(
          title: const Text('Transcrição'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Converte a fala das gravações em texto para você ler e pesquisar. '
                    'Tudo é processado neste dispositivo, sem enviar áudio para a internet.',
                    style: TextStyle(color: VL.textDim),
                  ),
                  const SizedBox(height: 16),
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: VL.error, fontSize: 13)),
                    const SizedBox(height: 12),
                  ],
                  for (final m in whisperModels) ...[
                    _ModelCard(
                      model: m,
                      installed: _installed[m.id] ?? false,
                      active: active == m.id,
                      downloading: _service.downloader.downloadingId == m.id,
                      progress: _service.downloader.progress,
                      busy: _service.downloader.downloadingId != null,
                      onDownload: () => _download(m),
                      onUse: () => _service.useModel(m),
                      onRemove: () => _remove(m),
                    ),
                    const SizedBox(height: 10),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Transcrever novas gravações automaticamente'),
                    value: settings.autoTranscribe,
                    onChanged: active == null ? null : _service.setAutoTranscribe,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'A transcrição automática pode conter erros e não substitui o áudio original.',
                    style: TextStyle(color: VL.textFaint, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => showLicensePage(context: context, applicationName: 'VoiceLog'),
              child: const Text('Licenças de terceiros'),
            ),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
          ],
        );
      },
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.model,
    required this.installed,
    required this.active,
    required this.downloading,
    required this.progress,
    required this.busy,
    required this.onDownload,
    required this.onUse,
    required this.onRemove,
  });

  final WhisperModel model;
  final bool installed;
  final bool active;
  final bool downloading;
  final double progress;
  final bool busy;
  final VoidCallback onDownload;
  final VoidCallback onUse;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final Widget action;
    if (downloading) {
      action = Text('${(progress * 100).floor()}%', style: const TextStyle(fontFeatures: VL.tabular));
    } else if (!installed) {
      action = OutlinedButton(onPressed: busy ? null : onDownload, child: const Text('Baixar'));
    } else if (!active) {
      action = OutlinedButton(onPressed: onUse, child: const Text('Usar'));
    } else {
      action = const Chip(label: Text('Em uso'), visualDensity: VisualDensity.compact);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: VL.panelHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? VL.success : VL.border, width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${model.label} · ${_megabytes(model.downloadSize)}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(model.description, style: const TextStyle(color: VL.textDim, fontSize: 12.5)),
            ]),
          ),
          const SizedBox(width: 8),
          action,
          if (installed && !downloading)
            IconButton(tooltip: 'Remover modelo', onPressed: onRemove, icon: const Icon(Icons.delete_outline, size: 20)),
        ]),
        if (downloading) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(value: progress, color: VL.text, backgroundColor: VL.border),
        ],
      ]),
    );
  }
}
