import 'dart:io';

import 'package:flutter/services.dart';

/// Native helpers on channel `voicelog/recording`: on Android, the foreground
/// service that keeps recording alive in the background; on Windows, the
/// default recording device.
class PlatformBridge {
  const PlatformBridge();

  static const _channel = MethodChannel('voicelog/recording');

  bool get _android => Platform.isAndroid;

  /// Throws a [PlatformException] if Android refuses to start the service.
  Future<void> startService() async {
    if (_android) await _channel.invokeMethod('start');
  }

  Future<void> updateService({required bool paused, required Duration elapsed}) async {
    if (_android) {
      await _channel.invokeMethod('update', {'paused': paused, 'elapsedMs': elapsed.inMilliseconds});
    }
  }

  Future<void> stopService() async {
    if (_android) await _channel.invokeMethod('stop');
  }

  /// Asks for notification permission (Android 13+) so the recording
  /// notification is visible. Recording works even if it is denied.
  Future<void> requestNotificationPermission() async {
    if (_android) await _channel.invokeMethod('requestNotificationPermission');
  }

  /// Free bytes on the volume holding [path], or null when unknown.
  Future<int?> freeBytes(String path) async {
    if (!_android) return null;
    return _channel.invokeMethod<int>('freeBytes', {'path': path});
  }

  /// Windows only: id of the "default recording device" from the sound
  /// settings. Elsewhere null, which lets the platform pick its default.
  Future<String?> defaultInputDeviceId() async {
    if (!Platform.isWindows) return null;
    return _channel.invokeMethod<String>('defaultInputDeviceId');
  }
}
