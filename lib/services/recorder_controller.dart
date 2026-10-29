import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import '../data/library_store.dart';
import '../models.dart';
import 'platform_bridge.dart';

enum RecorderPhase { idle, starting, recording, paused, stopping }

/// Outcome of a recording session, delivered on [RecorderController.results].
class RecordingResult {
  const RecordingResult(this.recording, {this.message});

  /// The saved recording, or null when nothing was captured.
  final Recording? recording;
  final String? message;
}

const _minFreeBytes = 50 * 1024 * 1024;

// Below -90 dBFS is digital silence; even a quiet room measures around -60.
const _silenceDb = -90.0;
// Amplitude arrives every 100 ms, so 30 samples is 3 seconds.
const _silenceSamples = 30;
const _waveformBars = 72;

/// Records AAC/ADTS audio straight to disk. The app-wide instance outlives
/// any screen, so recording continues while the user navigates.
///
/// Audio is streamed from the plugin and appended synchronously to the file,
/// so everything captured so far is on disk if the process dies.
class RecorderController extends ChangeNotifier {
  RecorderController(this.store, {this.bridge = const PlatformBridge()});

  final LibraryStore store;
  final PlatformBridge bridge;

  AudioRecorder? _recorder;
  AudioRecorder get _rec => _recorder ??= AudioRecorder();

  RecorderPhase phase = RecorderPhase.idle;
  Recording? _current;
  RandomAccessFile? _file;
  final _clock = Stopwatch();
  final List<double> levels = [];
  final List<int> _peaks = [];
  final List<StreamSubscription<Object?>> _subs = [];
  Completer<void>? _streamDone;
  Timer? _ticker;
  DateTime _lastSync = DateTime.now();

  final _results = StreamController<RecordingResult>.broadcast();
  Stream<RecordingResult> get results => _results.stream;

  Duration get elapsed => _clock.elapsed;
  bool get isActive => phase != RecorderPhase.idle;

  /// True while the microphone delivers digital silence, the signature of a
  /// muted, disconnected or virtual device (not of a quiet room, which still
  /// has some noise).
  bool noSignal = false;
  int _silentSamples = 0;

  /// Microphones the user can pick from.
  Future<List<InputDevice>> inputDevices() => _rec.listInputDevices();

  /// The user's chosen microphone if it is connected, else the system
  /// default recording device. Also returns a warning when the chosen one
  /// is missing.
  Future<(InputDevice?, String?)> _inputDevice() async {
    final settings = store.settings;
    String? warning;
    if (settings.inputDeviceId case final id?) {
      final match = (await inputDevices()).where((d) => d.id == id).firstOrNull;
      if (match != null) return (match, null);
      warning = 'O microfone "${settings.inputDeviceLabel ?? id}" não está conectado. '
          'Gravando com o microfone padrão.';
    }
    final defaultId = await bridge.defaultInputDeviceId().catchError((Object _) => null);
    return (defaultId == null ? null : InputDevice(id: defaultId, label: ''), warning);
  }

  /// Starts recording. Returns a user-facing error message, or null.
  Future<String?> start() async {
    if (phase != RecorderPhase.idle) return null;
    _setPhase(RecorderPhase.starting);
    try {
      if (!await _rec.hasPermission()) {
        _setPhase(RecorderPhase.idle);
        return 'Sem permissão para usar o microfone. Libere o acesso nas configurações do sistema.';
      }
      final free = await bridge.freeBytes(store.root.path);
      if (free != null && free < _minFreeBytes) {
        _setPhase(RecorderPhase.idle);
        return 'Espaço de armazenamento insuficiente para gravar.';
      }
      await bridge.requestNotificationPermission().catchError((Object _) {});

      final r = await store.beginRecording(DateTime.now());
      _current = r;
      _file = await store.audioFile(r).open(mode: FileMode.write);
      levels.clear();
      _peaks.clear();
      noSignal = false;
      _silentSamples = 0;

      final warnings = <String>[];
      try {
        await bridge.startService();
      } on Object {
        warnings.add('Não foi possível manter a gravação em segundo plano. Mantenha o app aberto.');
      }

      final (device, deviceWarning) = await _inputDevice();
      if (deviceWarning != null) warnings.add(deviceWarning);
      final stream = await _rec.startStream(RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        numChannels: 1,
        bitRate: 64000,
        device: device,
        audioInterruption: AudioInterruptionMode.pause,
      ));
      _streamDone = Completer();
      _subs
        ..add(stream.listen(_write, onError: (Object e) => _fail('Erro no microfone: $e'), onDone: _streamDone!.complete))
        ..add(_rec.onAmplitudeChanged(const Duration(milliseconds: 100)).listen(_onAmplitude))
        ..add(_rec.onStateChanged().listen(_onPluginState));
      _clock
        ..reset()
        ..start();
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => notifyListeners());
      _setPhase(RecorderPhase.recording);
      return warnings.isEmpty ? null : warnings.join(' ');
    } on Object catch (e) {
      await _abortStart();
      return 'Não foi possível iniciar a gravação: $e';
    }
  }

  void _write(Uint8List chunk) {
    final file = _file;
    if (file == null) return;
    try {
      file.writeFromSync(chunk);
      // Push to stable storage every few seconds to survive power loss too.
      final now = DateTime.now();
      if (now.difference(_lastSync) > const Duration(seconds: 5)) {
        file.flushSync();
        _lastSync = now;
      }
    } on FileSystemException catch (e) {
      final full = e.osError?.errorCode == 28 || e.osError?.errorCode == 112;
      _fail(full ? 'Armazenamento cheio.' : 'Erro ao gravar o arquivo: ${e.message}');
    }
  }

  void _onAmplitude(Amplitude a) {
    if (phase != RecorderPhase.recording) return;
    _silentSamples = a.current < _silenceDb ? _silentSamples + 1 : 0;
    noSignal = _silentSamples >= _silenceSamples;
    final level = ((a.current + 50) / 50).clamp(0.0, 1.0);
    levels.add(level);
    if (levels.length > 120) levels.removeAt(0);
    _peaks.add((level * 100).round());
  }

  /// Keeps the UI in sync when the system pauses or resumes recording,
  /// e.g. during a phone call.
  void _onPluginState(RecordState s) {
    if (s == RecordState.pause && phase == RecorderPhase.recording) {
      _markPaused(true);
    } else if (s == RecordState.record && phase == RecorderPhase.paused) {
      _markPaused(false);
    }
  }

  Future<void> pause() async {
    if (phase != RecorderPhase.recording) return;
    await _rec.pause();
    _markPaused(true);
  }

  Future<void> resume() async {
    if (phase != RecorderPhase.paused) return;
    await _rec.resume();
    _markPaused(false);
  }

  void _markPaused(bool paused) {
    if (paused) {
      _clock.stop();
    } else {
      _clock.start();
    }
    _setPhase(paused ? RecorderPhase.paused : RecorderPhase.recording);
    bridge.updateService(paused: paused, elapsed: elapsed).catchError((Object _) {});
  }

  /// Stops and saves. The recording lands in "Sem pasta" immediately, so the
  /// audio is kept even if the save dialog is dismissed.
  Future<void> stop({String? message}) async {
    if (phase != RecorderPhase.recording && phase != RecorderPhase.paused) return;
    _setPhase(RecorderPhase.stopping);
    final r = _current!;
    try {
      await _rec.stop();
    } on Object {
      // The file holds whatever was captured; keep going and save it.
    }
    await _streamDone?.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    await _cleanup();

    final length = await store.audioFile(r).length();
    if (length == 0) {
      await store.deleteRecording(r);
      _results.add(RecordingResult(null, message: message ?? 'Nenhum áudio foi captado.'));
      return;
    }
    var duration = await store.measure(r);
    if (duration == Duration.zero) duration = _clock.elapsed;
    await store.finishRecording(r, duration, _downsample(_peaks));
    _results.add(RecordingResult(r, message: message));
  }

  void _fail(String message) {
    if (phase == RecorderPhase.recording || phase == RecorderPhase.paused) {
      stop(message: '$message O áudio gravado até aqui foi salvo.');
    }
  }

  Future<void> _abortStart() async {
    try {
      await _rec.stop();
    } on Object {
      // Nothing was started.
    }
    await _cleanup();
    final r = _current;
    if (r != null) await store.deleteRecording(r);
    _setPhase(RecorderPhase.idle);
  }

  Future<void> _cleanup() async {
    _ticker?.cancel();
    _ticker = null;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final f = _file;
    _file = null;
    if (f != null) {
      try {
        await f.flush();
        await f.close();
      } on Object {
        // Data already written stays on disk.
      }
    }
    await bridge.stopService().catchError((Object _) {});
    _clock.stop();
    _current = null;
    _streamDone = null;
    phase = RecorderPhase.idle;
    notifyListeners();
  }

  static List<int> _downsample(List<int> peaks) {
    if (peaks.length <= _waveformBars) return List.of(peaks);
    final bucket = peaks.length / _waveformBars;
    return [
      for (var i = 0; i < _waveformBars; i++)
        peaks.sublist((i * bucket).floor(), min(peaks.length, ((i + 1) * bucket).ceil())).reduce(max),
    ];
  }

  void _setPhase(RecorderPhase p) {
    phase = p;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder?.dispose();
    _results.close();
    super.dispose();
  }
}
