package com.sanogueralorenzo.voice.overlay

import android.accessibilityservice.AccessibilityService
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import androidx.core.app.NotificationCompat
import com.sanogueralorenzo.voice.R

/** Owns the microphone foreground-service notification required while Overlay records. */
internal class OverlayRecordingForeground(
    private val service: AccessibilityService
) {
    fun start() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = service.getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL_ID,
                    service.getString(R.string.overlay_notification_channel),
                    NotificationManager.IMPORTANCE_LOW
                )
            )
        }

        val notification: Notification = NotificationCompat.Builder(
            service,
            NOTIFICATION_CHANNEL_ID
        )
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(service.getString(R.string.overlay_notification_title))
            .setContentText(service.getString(R.string.overlay_notification_text))
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            service.startForeground(
                NOTIFICATION_ID,
                notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            )
        } else {
            service.startForeground(NOTIFICATION_ID, notification)
        }
    }

    fun stop() {
        service.stopForeground(AccessibilityService.STOP_FOREGROUND_REMOVE)
    }

    private companion object {
        const val NOTIFICATION_CHANNEL_ID = "overlay_recording"
        const val NOTIFICATION_ID = 12057
    }
}
