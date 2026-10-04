package com.sanogueralorenzo.androidsteam.session

import android.app.Activity
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.window.OnBackInvokedDispatcher
import com.sanogueralorenzo.androidsteam.input.SteamSurface
import android.widget.TextView
import com.sanogueralorenzo.androidsteam.SteamApplication
import com.sanogueralorenzo.androidsteam.R

class SessionActivity : Activity(), SurfaceHolder.Callback {
    private val session get() = (application as SteamApplication).session
    private val observer: (SessionController.State) -> Unit = ::render
    private var started = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContentView(R.layout.activity_session)
        findViewById<SurfaceView>(R.id.surface).holder.apply { setFixedSize(1280, 720); addCallback(this@SessionActivity) }
        onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT) {
            findViewById<SteamSurface>(R.id.surface).backKey()
        }
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED)
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) window.insetsController?.apply {
            systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsets.Type.systemBars())
        }
    }

    override fun onStart() { super.onStart(); session.observe(observer) }
    override fun onStop() { session.removeObserver(observer); super.onStop() }
    override fun surfaceCreated(holder: SurfaceHolder) = Unit
    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        if (!started) {
            started = true
            if (session.state == SessionController.State.Running || session.state is SessionController.State.Working) session.attach(holder.surface)
            else {
                session.start(holder.surface, width, height, (display?.refreshRate?.times(1000))?.toInt() ?: 60_000)
                startForegroundService(Intent(this, SessionService::class.java))
            }
        } else session.attach(holder.surface)
    }
    override fun surfaceDestroyed(holder: SurfaceHolder) { session.attach(null) }

    private fun render(state: SessionController.State) {
        findViewById<TextView>(R.id.session_status).apply {
            visibility = if (state == SessionController.State.Running) View.GONE else View.VISIBLE
            text = when (state) {
                SessionController.State.Idle -> if (started) getString(R.string.session_stopped) else getString(R.string.starting_steam)
                is SessionController.State.Working -> state.message
                SessionController.State.Running -> ""
                SessionController.State.Stopping -> getString(R.string.stopping_steam)
                is SessionController.State.Failed -> state.message
            }
        }
    }
}
