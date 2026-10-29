package dev.voicelog.voicelog

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "voicelog/recording")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "start" -> {
                            RecordingService.start(this)
                            result.success(null)
                        }
                        "update" -> {
                            RecordingService.update(
                                this,
                                call.argument<Boolean>("paused") ?: false,
                                call.argument<Number>("elapsedMs")?.toLong() ?: 0L,
                            )
                            result.success(null)
                        }
                        "stop" -> {
                            RecordingService.stop(this)
                            result.success(null)
                        }
                        "freeBytes" -> result.success(StatFs(call.argument<String>("path")!!).availableBytes)
                        "requestNotificationPermission" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                                checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                                PackageManager.PERMISSION_GRANTED
                            ) {
                                requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                            }
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("recording_service", e.message, null)
                }
            }
    }
}
