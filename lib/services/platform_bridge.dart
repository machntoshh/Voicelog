import 'dart:io';

import 'package:flutter/services.dart';

/// Talks to the Android foreground service that keeps recording alive with
/// the screen locked or the app in the background. A no-op on desktop.
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
}
