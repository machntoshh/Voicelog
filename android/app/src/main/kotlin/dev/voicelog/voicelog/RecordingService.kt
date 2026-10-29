package dev.voicelog.voicelog

import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationChannelCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Foreground service of type "microphone". While it runs, Android keeps the
 * process alive and lets the app keep capturing audio with the screen locked
 * or another app in front. The audio itself is captured by the Flutter side;
 * this service only holds the foreground state, a wake lock and the
 * persistent notification.
 */
class RecordingService : Service() {
    companion object {
        private const val CHANNEL_ID = "recording"
        private const val NOTIFICATION_ID = 1
        private const val EXTRA_PAUSED = "paused"
        private const val EXTRA_ELAPSED_MS = "elapsedMs"

        /** Must be called while the app is in the foreground (Android 12+). */
        fun start(context: Context) {
            ContextCompat.startForegroundService(context, intent(context, paused = false, elapsedMs = 0))
        }

        /** Updates the notification; the service is already in the foreground. */
        fun update(context: Context, paused: Boolean, elapsedMs: Long) {
            context.startService(intent(context, paused, elapsedMs))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, RecordingService::class.java))
        }

        private fun intent(context: Context, paused: Boolean, elapsedMs: Long) =
            Intent(context, RecordingService::class.java)
                .putExtra(EXTRA_PAUSED, paused)
                .putExtra(EXTRA_ELAPSED_MS, elapsedMs)
    }

    private var inForeground = false
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val paused = intent?.getBooleanExtra(EXTRA_PAUSED, false) ?: false
        val elapsedMs = intent?.getLongExtra(EXTRA_ELAPSED_MS, 0) ?: 0
        val notification = buildNotification(paused, elapsedMs)
        if (!inForeground) {
            ensureChannel()
            val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            } else {
                0
            }
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, type)
            inForeground = true
            acquireWakeLock()
        } else if (NotificationManagerCompat.from(this).areNotificationsEnabled()) {
            NotificationManagerCompat.from(this).notify(NOTIFICATION_ID, notification)
        }
        // If the system kills the process, the recording ends there; the app
        // recovers the partial file on next launch, so no restart is wanted.
        return START_NOT_STICKY
    }

    /** Swiping the app away ends the Flutter engine and with it the capture. */
    override fun onTaskRemoved(rootIntent: Intent?) {
        stopSelf()
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "VoiceLog:recording").apply {
            setReferenceCounted(false)
            acquire(12 * 60 * 60 * 1000L)
        }
    }

    private fun ensureChannel() {
        val channel = NotificationChannelCompat.Builder(CHANNEL_ID, NotificationManagerCompat.IMPORTANCE_LOW)
            .setName("Gravação em andamento")
            .setDescription("Mostra quando o VoiceLog está gravando")
            .setShowBadge(false)
            .build()
        NotificationManagerCompat.from(this).createNotificationChannel(channel)
    }

    private fun buildNotification(paused: Boolean, elapsedMs: Long): android.app.Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val seconds = elapsedMs / 1000
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_mic)
            .setContentTitle(if (paused) "Gravação pausada" else "Gravando")
            .setContentText(
                if (paused) "Pausada em %02d:%02d · toque para abrir".format(seconds / 60, seconds % 60)
                else "VoiceLog · toque para abrir"
            )
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setShowWhen(!paused)
            .setUsesChronometer(!paused)
            .setWhen(System.currentTimeMillis() - elapsedMs)
            .build()
    }
}
