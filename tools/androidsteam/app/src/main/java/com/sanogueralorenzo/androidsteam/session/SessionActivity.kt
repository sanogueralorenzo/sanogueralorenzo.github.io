package com.sanogueralorenzo.androidsteam.session

import android.app.Activity
import android.app.AlertDialog
import android.Manifest
import android.content.Intent
import android.content.Context
import android.content.pm.PackageManager
import android.os.Bundle
import android.hardware.input.InputManager
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.window.OnBackInvokedDispatcher
import com.sanogueralorenzo.androidsteam.input.SteamSurface
import com.sanogueralorenzo.androidsteam.input.ControlProfile
import com.sanogueralorenzo.androidsteam.input.TouchControls
import com.sanogueralorenzo.androidsteam.input.TouchKey
import android.widget.TextView
import com.sanogueralorenzo.androidsteam.SteamApplication
import com.sanogueralorenzo.androidsteam.R
import com.sanogueralorenzo.androidsteam.SetupActivity

open class SessionActivity : Activity(), SurfaceHolder.Callback {
    companion object {
        internal fun intent(context: Context) = Intent(context,
            if ((context.applicationContext as SteamApplication).preparation.installed) SessionActivity::class.java else SetupActivity::class.java)
    }

    private val session get() = (application as SteamApplication).session
    private val observer: (SessionController.State) -> Unit = ::render
    private val gameObserver: (Int?) -> Unit = { appId ->
        renderControls(appId)
        if (appId == intent.getIntExtra("appId", 0)) played = true
        if (played && appId == null) finish()
    }
    private val surface get() = findViewById<SteamSurface>(R.id.surface)
    private val controls get() = findViewById<TouchControls>(R.id.touch_controls)
    private val devices = object : InputManager.InputDeviceListener {
        override fun onInputDeviceAdded(deviceId: Int) = Unit
        override fun onInputDeviceChanged(deviceId: Int) = Unit
        override fun onInputDeviceRemoved(deviceId: Int) { controls.release(); surface.releaseInput() }
    }
    private var started = false
    private var played = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContentView(R.layout.activity_session)
        played = savedInstanceState?.getBoolean("played") ?: false
        val appId = intent.getIntExtra("appId", 0)
        if (appId > 0 && savedInstanceState == null) try {
            session.requestGame(appId, intent.getBooleanExtra("install", false))
        } catch (failure: IllegalStateException) {
            android.widget.Toast.makeText(this, failure.message, android.widget.Toast.LENGTH_LONG).show()
        }
        findViewById<View>(R.id.return_library).setOnClickListener { finish() }
        controls.surface = surface
        findViewById<View>(R.id.game_controls).setOnClickListener {
            val appId = session.gameAppId ?: return@setOnClickListener
            controls.release(); surface.releaseInput()
            AlertDialog.Builder(this).setTitle(R.string.game_controls)
                .setSingleChoiceItems(ControlProfile.entries.map { it.label }.toTypedArray(), surface.profile.ordinal) { dialog, index ->
                    ControlProfile.save(this, appId, ControlProfile.entries[index])
                    renderControls(session.gameAppId)
                    dialog.dismiss()
                }.setNegativeButton(R.string.cancel, null).create().apply {
                    setOnDismissListener { surface.requestFocus() }
                    show()
                }
        }
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

    override fun onStart() {
        super.onStart(); session.observe(observer); session.observeGame(gameObserver)
        getSystemService(InputManager::class.java).registerInputDeviceListener(devices, null)
    }
    override fun onStop() {
        getSystemService(InputManager::class.java).unregisterInputDeviceListener(devices)
        controls.release(); surface.releaseInput()
        session.removeGameObserver(gameObserver); session.removeObserver(observer); super.onStop()
    }
    override fun surfaceCreated(holder: SurfaceHolder) = Unit
    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        if (!started) {
            started = true
            if (intent.getIntExtra("appId", 0) > 0 && session.needsRestart && session.state == SessionController.State.Running && session.gameAppId == null)
                session.restart(holder.surface, width, height, (display?.refreshRate?.times(1000))?.toInt() ?: 60_000)
            else if (session.state == SessionController.State.Running || session.state is SessionController.State.Working) session.attach(holder.surface)
            else {
                session.start(holder.surface, width, height, (display?.refreshRate?.times(1000))?.toInt() ?: 60_000)
                startForegroundService(Intent(this, SessionService::class.java))
            }
        } else session.attach(holder.surface)
    }
    override fun surfaceDestroyed(holder: SurfaceHolder) { session.detach(holder.surface) }
    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean("played", played)
        super.onSaveInstanceState(outState)
    }

    private fun renderControls(appId: Int?) {
        controls.release()
        surface.profile = appId?.let { ControlProfile.load(this, it) } ?: ControlProfile.TOUCH
        controls.extraKeys = appId?.let { TouchKey.load(this, it) }.orEmpty()
        controls.visibility = if (appId != null && surface.profile != ControlProfile.TOUCH) View.VISIBLE else View.GONE
        findViewById<View>(R.id.game_controls).visibility = if (appId != null) View.VISIBLE else View.GONE
    }

    private fun render(state: SessionController.State) {
        // Settings can change while the existing client is still starting.
        if (started && state == SessionController.State.Running && session.needsRestart &&
            intent.getIntExtra("appId", 0) > 0 && session.gameAppId == null && surface.holder.surface.isValid) {
            val frame = surface.holder.surfaceFrame
            session.restart(surface.holder.surface, frame.width(), frame.height(), (display?.refreshRate?.times(1000))?.toInt() ?: 60_000)
            return
        }
        findViewById<TextView>(R.id.action_status).apply {
            text = session.actionMessage
            visibility = if (session.actionMessage == null) View.GONE else View.VISIBLE
        }
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
