package com.sanogueralorenzo.amarchy

import android.app.Activity
import android.os.Bundle
import android.content.pm.ActivityInfo
import android.window.OnBackInvokedDispatcher
import com.sanogueralorenzo.amarchy.home.HomeScreen
import com.sanogueralorenzo.amarchy.desktop.DesktopScreen
import com.sanogueralorenzo.amarchy.session.Phase
import com.sanogueralorenzo.amarchy.session.WorkspaceService
import com.sanogueralorenzo.amarchy.session.WorkspaceState

class MainActivity : Activity() {
    private val workspace get() = (application as AmarchyApplication).workspace
    private lateinit var screen: HomeScreen
    private var desktop: DesktopScreen? = null
    private var wantsDesktop = true
    private val observer: (WorkspaceState) -> Unit = { render(it) }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        wantsDesktop = savedInstanceState?.getBoolean("desktop", true) ?: true
        screen = HomeScreen(this, { wantsDesktop = true; WorkspaceService.open(this); render(workspace.state) }, { workspace.stop() })
        setContentView(screen)
        onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT) {
            if (desktop != null) { wantsDesktop = false; showHome() } else moveTaskToBack(true)
        }
    }
    override fun onStart() { super.onStart(); workspace.observe(observer) }
    override fun onStop() { workspace.remove(observer); super.onStop() }
    override fun onSaveInstanceState(outState: Bundle) { outState.putBoolean("desktop", wantsDesktop); super.onSaveInstanceState(outState) }
    private fun render(state: WorkspaceState) {
        if (wantsDesktop && state.phase in setOf(Phase.STARTING, Phase.RUNNING, Phase.STOPPING)) {
            if (desktop == null) {
                requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                desktop = DesktopScreen(this, workspace) { wantsDesktop = false; showHome() }.also { setContentView(it) }
            }
            desktop!!.render(state)
        } else {
            if (desktop != null) showHome()
            screen.render(state)
        }
    }
    private fun showHome() {
        desktop?.hideKeyboard(); desktop = null
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        setContentView(screen); screen.render(workspace.state)
    }
}
