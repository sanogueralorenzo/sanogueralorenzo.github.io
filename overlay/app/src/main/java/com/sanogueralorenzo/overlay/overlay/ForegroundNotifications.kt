package com.sanogueralorenzo.overlay.overlay

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import androidx.core.app.NotificationCompat
import com.sanogueralorenzo.overlay.R

private const val FOREGROUND_CHANNEL_ID = "overlay_foreground"

const val OVERLAY_NOTIFICATION_ID = 1001

fun ensureForegroundChannel(context: Context) {
    val manager = context.getSystemService(NotificationManager::class.java) ?: return
    val channel = NotificationChannel(
        FOREGROUND_CHANNEL_ID,
        context.getString(R.string.foreground_channel_name),
        NotificationManager.IMPORTANCE_LOW
    ).apply {
        description = context.getString(R.string.foreground_channel_description)
    }
    manager.createNotificationChannel(channel)
}

fun buildOverlayNotification(
    context: Context,
    stopAction: PendingIntent? = null
): Notification {
    val builder = NotificationCompat.Builder(context, FOREGROUND_CHANNEL_ID)
        .setSmallIcon(R.drawable.ic_qs_black)
        .setContentTitle(context.getString(R.string.overlay_notification_title))
        .setContentText(context.getString(R.string.overlay_notification_body))
        .setCategory(NotificationCompat.CATEGORY_SERVICE)
        .setOngoing(true)
        .setOnlyAlertOnce(true)
    if (stopAction != null) {
        builder.addAction(
            android.R.drawable.ic_menu_close_clear_cancel,
            context.getString(R.string.stop_overlay_action),
            stopAction
        )
    }
    return builder.build()
}
