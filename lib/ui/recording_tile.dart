import 'dart:io';

import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../format.dart';
import '../models.dart';
import 'app_scope.dart';
import 'player_sheet.dart';
import 'recording_actions.dart';
import 'theme.dart';
import 'waveform.dart';

/// One recording in a list. Drag it onto a folder to move it (mouse drag on
/// desktop, long-press on touch); the ⋮ menu offers the same without gestures.
/// With a search [hit] in the transcript, shows the matching passage and opens
/// the player right where it is spoken.
class RecordingTile extends StatelessWidget {
  const RecordingTile({super.key, required this.recording, this.showFolder = false, this.hit});

  final Recording recording;
  final bool showFolder;
  final SearchHit? hit;

  @override
  Widget build(BuildContext context) {
    final card = _card(context);
    final feedback = Material(
      color: Colors.transparent,
      child: SizedBox(width: 280, child: Opacity(opacity: 0.9, child: _card(context, dragging: true))),
    );
    final placeholder = Opacity(opacity: 0.35, child: card);
    if (Platform.isAndroid || Platform.isIOS) {
      return LongPressDraggable<Recording>(
        data: recording,
        feedback: feedback,
        childWhenDragging: placeholder,
        child: card,
      );
    }
    return Draggable<Recording>(data: recording, feedback: feedback, childWhenDragging: placeholder, child: card);
  }

  Widget _card(BuildContext context, {bool dragging = false}) {
    final r = recording;
    final store = AppScope.of(context).store;
    final actions = RecordingActions(store);
    final folder = store.folderById(r.folderId)?.name ?? 'Sem pasta';
    const meta = TextStyle(color: VL.textDim, fontSize: 12.5, fontFeatures: VL.tabular);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(VL.radius),
        onTap: dragging || r.fileMissing ? null : () => showPlayer(context, r, startAt: hit?.at),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(children: [
            Container(
              width: 44,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(color: VL.panelHigh, borderRadius: BorderRadius.circular(10)),
              child: r.waveform.isEmpty
                  ? const Icon(Icons.graphic_eq, size: 20, color: VL.textDim)
                  : CustomPaint(
                      painter: WaveformPainter(
                        levels: _miniWave(r.waveform),
                        barWidth: 2,
                        gap: 1.5,
                        activeColor: VL.textDim,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('${formatDate(r.createdAt)} · ${formatTime(r.createdAt)} · ${formatDuration(r.duration)}',
                      style: meta),
                  if (showFolder) Text(folder, style: meta.copyWith(color: VL.textFaint)),
                  if (r.recovered) const _Badge('Recuperada', VL.warning),
                  if (r.fileMissing) const _Badge('Arquivo ausente', VL.error),
                  ...switch (r.transcriptStatus) {
                    TranscriptStatus.pending => const [_Badge('Na fila', VL.textDim)],
                    TranscriptStatus.running => const [_Badge('Transcrevendo', VL.textDim)],
                    TranscriptStatus.failed => const [_Badge('Transcrição falhou', VL.error)],
                    TranscriptStatus.done => const [Icon(Icons.subject_rounded, size: 15, color: VL.textFaint)],
                    TranscriptStatus.none => const <Widget>[],
                  },
                ]),
                if (hit?.snippet case final snippet?) ...[
                  const SizedBox(height: 6),
                  _Snippet(snippet, hit!.match),
                ],
              ]),
            ),
            if (!dragging)
              PopupMenuButton<String>(
                tooltip: 'Ações',
                icon: const Icon(Icons.more_vert, color: VL.textDim),
                onSelected: (v) => switch (v) {
                  'play' => showPlayer(context, r),
                  'rename' => actions.rename(context, r),
                  'move' => actions.move(context, r),
                  'export' => actions.export(context, r),
                  'transcribe' => actions.transcribe(context, r),
                  _ => actions.delete(context, r),
                },
                itemBuilder: (_) => [
                  if (!r.fileMissing) const PopupMenuItem(value: 'play', child: Text('Reproduzir')),
                  const PopupMenuItem(value: 'rename', child: Text('Renomear')),
                  const PopupMenuItem(value: 'move', child: Text('Mover para pasta')),
                  if (!r.fileMissing) const PopupMenuItem(value: 'export', child: Text('Exportar / compartilhar')),
                  if (!r.fileMissing &&
                      (r.transcriptStatus == TranscriptStatus.none || r.transcriptStatus == TranscriptStatus.failed))
                    const PopupMenuItem(value: 'transcribe', child: Text('Transcrever')),
                  const PopupMenuItem(value: 'delete', child: Text('Excluir', style: TextStyle(color: VL.red))),
                ],
              ),
          ]),
        ),
      ),
    );
  }

  static List<double> _miniWave(List<int> w) {
    const n = 10;
    final step = w.length / n;
    return [
      for (var i = 0; i < n; i++) 0.15 + w[(i * step).floor().clamp(0, w.length - 1)] / 100 * 0.85,
    ];
  }
}

/// Transcript excerpt with the matched words emphasized.
class _Snippet extends StatelessWidget {
  const _Snippet(this.text, this.match);

  final String text;
  final (int, int)? match;

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(color: VL.textDim, fontSize: 13, height: 1.3);
    final m = match;
    return Text.rich(
      m == null
          ? TextSpan(text: text)
          : TextSpan(children: [
              TextSpan(text: text.substring(0, m.$1)),
              TextSpan(
                text: text.substring(m.$1, m.$2),
                style: const TextStyle(color: VL.text, fontWeight: FontWeight.w600, backgroundColor: VL.redSoft),
              ),
              TextSpan(text: text.substring(m.$2)),
            ]),
      style: base,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(color: color, fontSize: 11)),
      );
}
