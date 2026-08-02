package com.example.bully_client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * Holds a low-priority persistent notification so Android keeps this
 * process (and the Dart isolate's already-open WebSocket + WebRTC call
 * signaling running inside it) alive and unthrottled while the app is
 * backgrounded. It does no work of its own — the existing Flutter engine
 * keeps running exactly as it does in the foreground; this only stops the
 * OS from suspending/killing that process.
 */
class BullyForegroundService : Service() {
    private val channelId = "bully_background"
    private val notificationId = 42

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(notificationId, buildNotification())
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(channelId, "Bully фон", NotificationManager.IMPORTANCE_LOW)
            manager.createNotificationChannel(channel)
        }

        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, openIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return Notification.Builder(this, channelId)
            .setContentTitle("Bully")
            .setContentText("Соединение активно — сообщения и звонки доходят в фоне")
            .setSmallIcon(applicationInfo.icon)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }
}
