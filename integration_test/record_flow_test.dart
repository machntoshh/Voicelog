import 'dart:io';

import 'package:audio_decoder/audio_decoder.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voicelog/data/library_store.dart';
import 'package:voicelog/models.dart';
import 'package:voicelog/services/platform_bridge.dart';
import 'package:voicelog/services/recorder_controller.dart';
import 'package:voicelog/services/transcription_service.dart';

/// Records from the real microphone, so it needs a device with one:
/// `flutter test integration_test -d windows` (or `-d <android-device-id>`).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('record, pause, resume, stop, reopen and play back', (tester) async {
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('voicelog_it');
      addTearDown(() => root.delete(recursive: true));
      final store = LibraryStore(root);
      await store.load();
      final rec = RecorderController(store);
      final result = rec.results.first;

      expect(await rec.start(), isNull);
      expect(rec.phase, RecorderPhase.recording);
      await Future<void>.delayed(const Duration(seconds: 2));
      await rec.pause();
      expect(rec.phase, RecorderPhase.paused);
      final pausedAt = rec.elapsed;
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(rec.elapsed, pausedAt, reason: 'clock stops while paused');
      await rec.resume();
      await Future<void>.delayed(const Duration(seconds: 2));
      await rec.stop();

      final r = (await result).recording!;
      expect(r.status, RecordingStatus.ready);
      expect(r.folderId, isNull);
      expect(r.waveform, isNotEmpty);
      // ~4 s of audio; the paused second is not in the file.
      expect(r.duration.inMilliseconds, inInclusiveRange(3300, 4700));

      final reopened = LibraryStore(root);
      await reopened.load();
      expect(reopened.recordings.single.id, r.id);
      expect(reopened.recoveredOnLoad, 0);

      final player = AudioPlayer();
      await player.setSource(DeviceFileSource(store.audioFile(r).path, mimeType: 'audio/aac'));
      final playable = await player.getDuration();
      await player.dispose();
      expect(playable, isNotNull);
      expect((playable! - r.duration).abs(), lessThan(const Duration(milliseconds: 500)));

      // The transcription pipeline must be able to decode the recorded ADTS
      // file to 16 kHz mono PCM.
      final wav = '${root.path}/decoded.wav';
      await AudioDecoder.convertToWav(store.audioFile(r).path, wav, sampleRate: 16000, channels: 1, bitDepth: 16);
      final raf = await File(wav).open();
      final (_, pcmBytes) = await readWavPcmRange(raf);
      await raf.close();
      final decoded = Duration(microseconds: pcmBytes ~/ 2 * 1000000 ~/ 16000);
      expect((decoded - r.duration).abs(), lessThan(const Duration(milliseconds: 300)));
      rec.dispose();
    });
  });

  // Regression: without an explicit device, Windows recorded from the default
  // *communications* microphone, which can be a silent virtual device.
  testWidgets('Windows: records from the default recording device and hears sound', (tester) async {
    await tester.runAsync(() async {
      final root = await Directory.systemTemp.createTemp('voicelog_it_mic');
      addTearDown(() => root.delete(recursive: true));
      final store = LibraryStore(root);
      await store.load();
      final rec = RecorderController(store);

      final defaultId = await const PlatformBridge().defaultInputDeviceId();
      expect(defaultId, isNotNull);
      final devices = await rec.inputDevices();
      expect(devices.map((d) => d.id), contains(defaultId));

      expect(await rec.start(), isNull);
      await Future<void>.delayed(const Duration(seconds: 5));
      expect(rec.noSignal, isFalse, reason: 'default microphone delivered digital silence');
      await rec.stop();
      rec.dispose();
    });
  }, skip: !Platform.isWindows);
}
