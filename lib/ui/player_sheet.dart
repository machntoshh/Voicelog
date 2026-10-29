import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../format.dart';
import '../models.dart';
import 'app_scope.dart';
import 'recording_actions.dart';
import 'theme.dart';
import 'waveform.dart';

/// Opens the player; [startAt] jumps to a point, e.g. a search match.
Future<void> showPlayer(BuildContext context, Recording r, {Duration? startAt}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (_) => PlayerSheet(recording: r, startAt: startAt),
    );

const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

class PlayerSheet extends StatefulWidget {
  const PlayerSheet({super.key, required this.recording, this.startAt});

  final Recording recording;
  final Duration? startAt;

  @override
  State<PlayerSheet> createState() => _PlayerSheetState();
}

class _PlayerSheetState extends State<PlayerSheet> {
  final _player = AudioPlayer();
  final _subs = <StreamSubscription<Object?>>[];
  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;
  double _speed = 1;
  String? _error;

  Recording get r => widget.recording;
  Duration get _total => (_duration ?? Duration.zero) > Duration.zero ? _duration! : r.duration;

  @override
  void initState() {
    super.initState();
    _subs
      ..add(_player.onPositionChanged.listen((p) => setState(() => _position = p)))
      ..add(_player.onDurationChanged.listen((d) => setState(() => _duration = d)))
      ..add(_player.onPlayerStateChanged.listen((s) => setState(() => _playing = s == PlayerState.playing)))
      ..add(_player.onPlayerComplete.listen((_) => setState(() => _position = _total)));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final store = AppScope.of(context).store;
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSource(DeviceFileSource(store.audioFile(r).path, mimeType: 'audio/aac'));
      if (widget.startAt case final at?) await _seek(at);
      await _player.resume();
    } on Object {
      if (mounted) setState(() => _error = 'Não foi possível abrir este áudio.');
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      if (_position >= _total - const Duration(milliseconds: 200)) await _player.seek(Duration.zero);
      await _player.resume();
    }
  }

  Future<void> _seek(Duration to) async {
    final clamped = to < Duration.zero ? Duration.zero : (to > _total ? _total : to);
    setState(() => _position = clamped);
    await _player.seek(clamped);
  }

  Future<void> _cycleSpeed() async {
    final next = _speeds[(_speeds.indexOf(_speed) + 1) % _speeds.length];
    await _player.setPlaybackRate(next);
    setState(() => _speed = next);
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final store = scope.store;
    final actions = RecordingActions(store);
    final folder = store.folderById(r.folderId)?.name ?? 'Sem pasta';
    final progress = _total.inMilliseconds == 0 ? 0.0 : _position.inMilliseconds / _total.inMilliseconds;
    const meta = TextStyle(color: VL.textDim, fontSize: 13, fontFeatures: VL.tabular);

    return ListenableBuilder(
      listenable: Listenable.merge([store, scope.transcriber]),
      builder: (context, _) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(r.name, style: Theme.of(context).textTheme.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('${formatDate(r.createdAt)} · ${formatTime(r.createdAt)} · $folder', style: meta),
            const SizedBox(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: VL.error)),
              )
            else ...[
              _Scrubber(
                waveform: r.waveform,
                progress: progress.clamp(0.0, 1.0),
                onSeek: (f) => _seek(_total * f),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Text(formatDuration(_position), style: meta),
                const Spacer(),
                Text(formatDuration(_total), style: meta),
              ]),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(
                  width: 64,
                  child: TextButton(
                    onPressed: _cycleSpeed,
                    child: Text('${_speed.toString().replaceAll(RegExp(r'\.0$'), '')}×', style: meta),
                  ),
                ),
                IconButton(
                  tooltip: 'Voltar 10 s',
                  iconSize: 30,
                  onPressed: () => _seek(_position - const Duration(seconds: 10)),
                  icon: const Icon(Icons.replay_10_rounded),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: _playing ? 'Pausar' : 'Reproduzir',
                  iconSize: 36,
                  style: IconButton.styleFrom(
                      backgroundColor: VL.text, foregroundColor: VL.bg, fixedSize: const Size(64, 64)),
                  onPressed: _toggle,
                  icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Avançar 10 s',
                  iconSize: 30,
                  onPressed: () => _seek(_position + const Duration(seconds: 10)),
                  icon: const Icon(Icons.forward_10_rounded),
                ),
                const SizedBox(width: 64),
              ]),
            ],
            const SizedBox(height: 12),
            _TranscriptPanel(recording: r, onSeek: _seek, onTranscribe: () => actions.transcribe(context, r)),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Wrap(alignment: WrapAlignment.spaceEvenly, children: [
              _Action(icon: Icons.edit_outlined, label: 'Renomear', onTap: () => actions.rename(context, r)),
              _Action(icon: Icons.drive_file_move_outlined, label: 'Mover', onTap: () => actions.move(context, r)),
              _Action(icon: Icons.ios_share_rounded, label: 'Exportar', onTap: () => actions.export(context, r)),
              _Action(
                icon: Icons.delete_outline,
                label: 'Excluir',
                color: VL.red,
                onTap: () async {
                  await _player.stop();
                  if (!context.mounted) return;
                  if (await actions.delete(context, r) && context.mounted) Navigator.pop(context);
                },
              ),
            ]),
          ],
        ),
      ),
      ),
    );
  }
}

/// Transcript state for one recording: offer, queue, progress, text or error.
class _TranscriptPanel extends StatelessWidget {
  const _TranscriptPanel({required this.recording, required this.onSeek, required this.onTranscribe});

  final Recording recording;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onTranscribe;

  @override
  Widget build(BuildContext context) {
    final r = recording;
    final transcriber = AppScope.of(context).transcriber;
    const dim = TextStyle(color: VL.textDim, fontSize: 13);
    final Widget body = switch (r.transcriptStatus) {
      TranscriptStatus.none => Row(children: [
          const Expanded(child: Text('Sem transcrição', style: dim)),
          TextButton.icon(
            onPressed: onTranscribe,
            icon: const Icon(Icons.subject_rounded, size: 18),
            label: const Text('Transcrever'),
          ),
        ]),
      TranscriptStatus.pending => const Text('Na fila para transcrição…', style: dim),
      TranscriptStatus.running => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
            transcriber.current == r && transcriber.progress != null
                ? 'Transcrevendo… ${(transcriber.progress! * 100).floor()}%'
                : 'Preparando o áudio…',
            style: dim,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: transcriber.current == r ? transcriber.progress : null,
            color: VL.text,
            backgroundColor: VL.border,
          ),
        ]),
      TranscriptStatus.failed => Row(children: [
          const Icon(Icons.error_outline, color: VL.error, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(r.transcriptError ?? 'A transcrição falhou.', style: const TextStyle(color: VL.error, fontSize: 13))),
          TextButton(onPressed: onTranscribe, child: const Text('Tentar novamente')),
        ]),
      TranscriptStatus.done => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (r.transcript.isEmpty)
            const Text('Nenhuma fala foi detectada nesta gravação.', style: dim)
          else
            for (final s in r.transcript)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onSeek(s.start),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 52,
                      child: Text(formatDuration(s.start),
                          style: const TextStyle(color: VL.textFaint, fontSize: 12.5, fontFeatures: VL.tabular)),
                    ),
                    Expanded(child: Text(s.text, style: const TextStyle(height: 1.35))),
                  ]),
                ),
              ),
          const SizedBox(height: 8),
          const Text(
            'Transcrição automática: pode conter erros e não substitui o áudio original.',
            style: TextStyle(color: VL.textFaint, fontSize: 11.5),
          ),
        ]),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: VL.panelHigh, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('TRANSCRIÇÃO', style: TextStyle(fontSize: 11, letterSpacing: 1.4, color: VL.textFaint)),
        const SizedBox(height: 8),
        body,
      ]),
    );
  }
}

/// Seek bar drawn as the recording's waveform (or a plain slider when the
/// waveform is unknown, e.g. for recovered recordings).
class _Scrubber extends StatelessWidget {
  const _Scrubber({required this.waveform, required this.progress, required this.onSeek});

  final List<int> waveform;
  final double progress;
  final ValueChanged<double> onSeek;

  @override
  Widget build(BuildContext context) {
    if (waveform.isEmpty) {
      return Slider(value: progress, onChanged: onSeek, activeColor: VL.text, inactiveColor: VL.border);
    }
    return LayoutBuilder(builder: (context, c) {
      void seekAt(Offset p) => onSeek((p.dx / c.maxWidth).clamp(0.0, 1.0));
      return Semantics(
        slider: true,
        label: 'Posição da reprodução',
        value: '${(progress * 100).round()}%',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seekAt(d.localPosition),
          onHorizontalDragUpdate: (d) => seekAt(d.localPosition),
          child: SizedBox(
            height: 56,
            width: double.infinity,
            child: CustomPaint(
              painter: WaveformPainter(
                levels: [for (final v in waveform) 0.08 + v / 100 * 0.92],
                progress: progress,
                barWidth: 4,
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.color = VL.textDim});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ]),
        ),
      );
}
