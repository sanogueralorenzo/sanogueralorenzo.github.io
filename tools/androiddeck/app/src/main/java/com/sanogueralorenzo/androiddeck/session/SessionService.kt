package com.sanogueralorenzo.androiddeck.session

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import com.sanogueralorenzo.androiddeck.DeckApplication
import com.sanogueralorenzo.androiddeck.R

/** Keeps the controller's user-started session alive during Steam Guard. */
class SessionService : Service() {
    private val session get() = (application as DeckApplication).session
    private val observer: (SessionController.State) -> Unit = { state ->
        if (state == SessionController.State.Idle || state is SessionController.State.Failed) stopSelf()
    }

    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("steam-session", getString(R.string.session_channel), NotificationManager.IMPORTANCE_LOW))
        val resume = PendingIntent.getActivity(this, 0,
            Intent(this, SessionActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 1, Intent(this, SessionService::class.java).setAction("stop"), PendingIntent.FLAG_IMMUTABLE)
        startForeground(1, Notification.Builder(this, "steam-session")
            .setSmallIcon(R.drawable.ic_deck).setContentTitle(getString(R.string.app_name))
            .setContentText(getString(R.string.session_notification)).setContentIntent(resume)
            .setCategory(Notification.CATEGORY_SERVICE).setOngoing(true)
            .addAction(Notification.Action.Builder(null, getString(R.string.stop_steam), stop).build()).build(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        session.observe(observer)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "stop") session.stop()
        return START_NOT_STICKY
    }
    override fun onTaskRemoved(rootIntent: Intent?) { session.stop() }
    override fun onDestroy() { session.removeObserver(observer); session.stop(); super.onDestroy() }
    override fun onBind(intent: Intent?) = null
}
