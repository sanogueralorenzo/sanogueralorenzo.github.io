package com.sanogueralorenzo.overlay.overlay

import android.app.Service
import android.app.Service.STOP_FOREGROUND_REMOVE
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.service.quicksettings.TileService
import android.view.MotionEvent
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.FrameLayout
import com.sanogueralorenzo.overlay.OVERLAY_NOTIFICATION_ID
import com.sanogueralorenzo.overlay.SettingsRepository
import com.sanogueralorenzo.overlay.autolock.AutoLockScheduler
import com.sanogueralorenzo.overlay.buildOverlayNotification
import com.sanogueralorenzo.overlay.ensureForegroundChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

class OverlayService : Service() {
    companion object {
        const val ACTION_STOP = "com.sanogueralorenzo.overlay.action.STOP_OVERLAY"

        @Volatile
        var isRunning: Boolean = false

        fun requestTileUpdate(context: Context) {
            val component = ComponentName(context, OverlayTileService::class.java)
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

    private var windowManager: WindowManager? = null
    private var overlayView: FrameLayout? = null
    private var receiverRegistered: Boolean = false
    private val handler = Handler(Looper.getMainLooper())
    @Volatile
    private var longPressDismissEnabled: Boolean = false
    private val longPressRunnable = Runnable {
        if (longPressDismissEnabled) {
            stopSelf()
        }
    }
    private val settingsRepository by lazy { SettingsRepository(applicationContext) }
    private val autoLockScheduler by lazy {
        AutoLockScheduler(
            context = this,
            handler = handler,
            settingsRepository = settingsRepository,
            serviceScope = serviceScope,
            stopSelf = { stopSelf() },
            stopOnInvalidConfig = false
        )
    }
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()
        ensureForegroundChannel(this)
        val stopIntent = Intent(this, OverlayService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            0,
            stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        startForeground(
            OVERLAY_NOTIFICATION_ID,
            buildOverlayNotification(this, stopPendingIntent)
        )
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        overlayView = FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
        }
        val longPressTimeoutMs = ViewConfiguration.getLongPressTimeout().toLong()
        overlayView?.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    handler.postDelayed(longPressRunnable, longPressTimeoutMs)
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    handler.removeCallbacks(longPressRunnable)
                }
            }
            true
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_FULLSCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.OPAQUE
        )
        try {
            windowManager?.addView(overlayView, params)
        } catch (_: SecurityException) {
            stopSelf()
            return
        }
        val screenOffFilter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        registerReceiver(
            screenOffReceiver,
            screenOffFilter,
            Context.RECEIVER_NOT_EXPORTED
        )
        receiverRegistered = true
        isRunning = true
        serviceScope.launch {
            settingsRepository.longPressDismissEnabledFlow().collect { enabled ->
                longPressDismissEnabled = enabled
            }
        }
        requestTileUpdate(this)
        autoLockScheduler.start()
    }

    override fun onDestroy() {
        stopForegroundNotification()
        overlayView?.let { view ->
            if (view.parent != null) {
                windowManager?.removeView(view)
            }
        }
        overlayView = null
        if (receiverRegistered) {
            unregisterReceiver(screenOffReceiver)
            receiverRegistered = false
        }
        autoLockScheduler.clear()
        handler.removeCallbacks(longPressRunnable)
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
