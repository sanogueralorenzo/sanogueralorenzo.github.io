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
import android.os.IBinder
import android.service.quicksettings.TileService
import android.view.Gravity
import android.view.View
import android.view.WindowManager

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
                immersiveModeController.disableStatusBarImmersiveMode()
                stopSelf()
            }
        }
    }

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var receiverRegistered: Boolean = false
    private val immersiveModeController by lazy { ImmersiveModeController(applicationContext) }

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
        val screenOffFilter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        registerReceiver(
            screenOffReceiver,
            screenOffFilter,
            Context.RECEIVER_NOT_EXPORTED
        )
        receiverRegistered = true
        isRunning = true
        addOverlay()
        requestTileUpdate(this)
    }

    override fun onDestroy() {
        stopForegroundNotification()
        immersiveModeController.disableStatusBarImmersiveMode()
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
        isRunning = false
        requestTileUpdate(this)
        super.onDestroy()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            immersiveModeController.disableStatusBarImmersiveMode()
            stopSelf()
            return START_NOT_STICKY
        }
        immersiveModeController.enableStatusBarImmersiveMode()
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun stopForegroundNotification() {
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun addOverlay() {
        if (overlayView != null) {
            return
        }
        val blackView = View(this).apply {
            setBackgroundColor(Color.BLACK)
            setOnTouchListener { _, _ ->
                true
            }
        }
        try {
            windowManager?.addView(blackView, createOverlayParams())
            overlayView = blackView
        } catch (_: SecurityException) {
            stopSelf()
        }
    }

    private fun createOverlayParams(): WindowManager.LayoutParams {
        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_FULLSCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            // Request edge-to-edge layout; system bars still remain above application overlays.
            layoutInDisplayCutoutMode =
                WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            setFitInsetsTypes(0)
        }
    }
}
