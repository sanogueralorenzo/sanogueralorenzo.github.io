package com.sanogueralorenzo.androidsteam.setup

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.SystemClock
import com.sanogueralorenzo.androidsteam.R
import com.sanogueralorenzo.androidsteam.SetupActivity
import com.sanogueralorenzo.androidsteam.SteamApplication

/** Foreground lifetime for the user's Download; preparation stays in its single owner. */
class SetupService : Service() {
    private val setup get() = (application as SteamApplication).setup
    private var observing = false
    private var lastNotification = 0L
    private val observer: (SetupController.State) -> Unit = { state ->
        if (state !is SetupController.State.Working) stopSelf()
        else if (SystemClock.elapsedRealtime() - lastNotification >= 1_000) {
            lastNotification = SystemClock.elapsedRealtime()
            getSystemService(NotificationManager::class.java).notify(2, notification(state.message))
        }
    }
    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("steam-setup", "Android Steam setup", NotificationManager.IMPORTANCE_LOW))
        startForeground(2, notification("Preparing Android Steam…"), ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
    }
    private fun notification(message: String): Notification {
        val resume = PendingIntent.getActivity(this, 2, Intent(this, SetupActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val cancel = PendingIntent.getService(this, 3, Intent(this, SetupService::class.java).setAction("cancel"), PendingIntent.FLAG_IMMUTABLE)
        return Notification.Builder(this, "steam-setup").setSmallIcon(R.drawable.ic_steam)
            .setContentTitle(getString(R.string.app_name)).setContentText(message).setContentIntent(resume)
            .setOngoing(true).setOnlyAlertOnce(true)
            .addAction(Notification.Action.Builder(null, getString(R.string.cancel), cancel).build()).build()
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "cancel") setup.stop() else setup.install()
        if (!observing) { observing = true; setup.observe(observer) }
        return START_NOT_STICKY
    }
    override fun onTimeout(startId: Int, fgsType: Int) { setup.stop(); stopSelf() }
    override fun onTaskRemoved(rootIntent: Intent?) { setup.stop(); stopSelf() }
    override fun onDestroy() { if (observing) setup.removeObserver(observer); setup.stop(); super.onDestroy() }
    override fun onBind(intent: Intent?) = null
}
