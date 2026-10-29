import 'package:flutter/material.dart';

import '../format.dart';
import '../services/recorder_controller.dart';
import 'app_scope.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'waveform.dart';

/// Fixed bottom bar: a single red button when idle, live controls while
/// recording. Lives in the Home scaffold, so it stays visible everywhere.
class RecorderBar extends StatelessWidget {
  const RecorderBar({super.key});

  @override
  Widget build(BuildContext context) {
    final rec = AppScope.of(context).recorder;
    return ListenableBuilder(
      listenable: rec,
      builder: (context, _) {
        final active = rec.phase == RecorderPhase.recording ||
            rec.phase == RecorderPhase.paused ||
            rec.phase == RecorderPhase.stopping;
        return Material(
          color: VL.surface,
          child: SafeArea(
            top: false,
            child: Container(
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: VL.border, width: 0.6))),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: active ? _ActiveControls(rec: rec) : _IdleButton(rec: rec),
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> _start(BuildContext context, RecorderController rec) async {
  final error = await rec.start();
  if (error != null && context.mounted) showMessage(context, error, error: true);
}

class _IdleButton extends StatelessWidget {
  const _IdleButton({required this.rec});

  final RecorderController rec;

  @override
  Widget build(BuildContext context) {
    final starting = rec.phase == RecorderPhase.starting;
    return Center(
      key: const ValueKey('idle'),
      heightFactor: 1,
      child: Semantics(
        button: true,
        label: 'Iniciar gravação',
        child: Tooltip(
          message: 'Gravar',
          child: InkResponse(
            onTap: starting ? null : () => _start(context, rec),
            radius: 40,
            child: Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: VL.red,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: VL.red.withValues(alpha: 0.35), blurRadius: 18)],
              ),
              child: starting
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(strokeWidth: 2, color: VL.text),
                    )
                  : const Icon(Icons.mic, color: VL.text, size: 30),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveControls extends StatelessWidget {
  const _ActiveControls({required this.rec});

  final RecorderController rec;

  @override
  Widget build(BuildContext context) {
    final paused = rec.phase == RecorderPhase.paused;
    final stopping = rec.phase == RecorderPhase.stopping;
    return SizedBox(
      key: const ValueKey('active'),
      height: 62,
      child: Row(children: [
        _RecDot(paused: paused),
        const SizedBox(width: 10),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(paused ? 'PAUSADO' : 'GRAVANDO',
                style: TextStyle(
                    fontSize: 11, letterSpacing: 1.4, color: paused ? VL.warning : VL.red, fontWeight: FontWeight.w600)),
            Text(formatDuration(rec.elapsed),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500, fontFeatures: VL.tabular)),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SizedBox(
            height: 40,
            child: CustomPaint(
              painter: WaveformPainter(
                levels: rec.levels,
                alignRight: true,
                activeColor: paused ? VL.textFaint : VL.red,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          tooltip: paused ? 'Retomar' : 'Pausar',
          iconSize: 26,
          onPressed: stopping ? null : (paused ? rec.resume : rec.pause),
          icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Finalizar',
          iconSize: 26,
          style: IconButton.styleFrom(backgroundColor: VL.red, foregroundColor: VL.text),
          onPressed: stopping ? null : rec.stop,
          icon: stopping
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.stop_rounded),
        ),
      ]),
    );
  }
}

class _RecDot extends StatefulWidget {
  const _RecDot({required this.paused});

  final bool paused;

  @override
  State<_RecDot> createState() => _RecDotState();
}

class _RecDotState extends State<_RecDot> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: widget.paused ? const AlwaysStoppedAnimation(1) : Tween(begin: 0.35, end: 1.0).animate(_anim),
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: widget.paused ? VL.warning : VL.red, shape: BoxShape.circle),
        ),
      );
}
