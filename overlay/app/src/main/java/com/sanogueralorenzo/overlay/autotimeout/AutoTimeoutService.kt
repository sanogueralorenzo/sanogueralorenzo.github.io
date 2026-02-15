package com.sanogueralorenzo.overlay.autotimeout

import android.app.Service
import android.app.Service.STOP_FOREGROUND_REMOVE
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.service.quicksettings.TileService
import com.sanogueralorenzo.overlay.AUTO_TIMEOUT_NOTIFICATION_ID
import com.sanogueralorenzo.overlay.SettingsRepository
import com.sanogueralorenzo.overlay.autolock.AutoLockScheduler
import com.sanogueralorenzo.overlay.buildAutoTimeoutNotification
import com.sanogueralorenzo.overlay.ensureForegroundChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel

class AutoTimeoutService : Service() {
    companion object {
        const val ACTION_STOP = "com.sanogueralorenzo.overlay.action.STOP_AUTO_TIMEOUT"

        @Volatile
        var isRunning: Boolean = false

        fun requestTileUpdate(context: Context) {
            val component = ComponentName(context, AutoTimeoutTileService::class.java)
            TileService.requestListeningState(context, component)
        }
    }

    private val screenOffReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (Intent.ACTION_SCREEN_OFF == intent.action) {
                stopSelf()
            }
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var receiverRegistered: Boolean = false
    private val settingsRepository by lazy { SettingsRepository(applicationContext) }
    private val autoLockScheduler by lazy {
        AutoLockScheduler(
            context = this,
            handler = handler,
            settingsRepository = settingsRepository,
            serviceScope = serviceScope,
            stopSelf = { stopSelf() },
            stopOnInvalidConfig = true
        )
    }
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()
        ensureForegroundChannel(this)
        val stopIntent = Intent(this, AutoTimeoutService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            1,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        startForeground(
            AUTO_TIMEOUT_NOTIFICATION_ID,
            buildAutoTimeoutNotification(this, stopPendingIntent)
        )
        val screenOffFilter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        registerReceiver(
            screenOffReceiver,
            screenOffFilter,
            Context.RECEIVER_NOT_EXPORTED
        )
        receiverRegistered = true
        isRunning = true
        requestTileUpdate(this)
        autoLockScheduler.start()
    }

    override fun onDestroy() {
        stopForegroundNotification()
        if (receiverRegistered) {
            unregisterReceiver(screenOffReceiver)
            receiverRegistered = false
        }
        autoLockScheduler.clear()
        serviceScope.cancel()
        isRunning = false
        requestTileUpdate(this)
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun stopForegroundNotification() {
        stopForeground(STOP_FOREGROUND_REMOVE)
    }
}
