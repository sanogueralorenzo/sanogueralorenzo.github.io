package com.sanogueralorenzo.amarchy.session

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import com.sanogueralorenzo.amarchy.AmarchyApplication
import com.sanogueralorenzo.amarchy.MainActivity
import com.sanogueralorenzo.amarchy.R

class WorkspaceService : Service() {
    private val workspace get() = (application as AmarchyApplication).workspace
    private val observer: (WorkspaceState) -> Unit = { state ->
        if (state.phase in setOf(Phase.WELCOME, Phase.FAILED)) stopSelf()
        else startForeground(1, notification(state.detail), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
    }
    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("workspace", getString(R.string.notification_channel), NotificationManager.IMPORTANCE_LOW))
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(1, notification("Preparing your workspace"), ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        if (intent?.action == "stop") workspace.stop() else workspace.open()
        workspace.observe(observer)
        return START_NOT_STICKY
    }
    override fun onTaskRemoved(rootIntent: Intent?) { if (workspace.state.phase == Phase.PREPARING) workspace.stop() }
    override fun onDestroy() {
        workspace.remove(observer)
        if (workspace.state.phase !in setOf(Phase.WELCOME, Phase.FAILED)) workspace.stop()
        stopForeground(STOP_FOREGROUND_REMOVE); super.onDestroy()
    }
    override fun onBind(intent: Intent?): IBinder? = null
    private fun notification(detail: String): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this, 1, Intent(this, WorkspaceService::class.java).setAction("stop"), PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, "workspace").setSmallIcon(R.drawable.amarchy_icon).setContentTitle("Amarchy")
            .setContentText(detail).setContentIntent(open).setOnlyAlertOnce(true).setOngoing(true)
            .addAction(Notification.Action.Builder(null, if (workspace.state.phase == Phase.RUNNING) "Close desktop" else "Cancel", stop).build()).build()
    }
    companion object { fun open(context: Context) { context.startForegroundService(Intent(context, WorkspaceService::class.java)) } }
}
