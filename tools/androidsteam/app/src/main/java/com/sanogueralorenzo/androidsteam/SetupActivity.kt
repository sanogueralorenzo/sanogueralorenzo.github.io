package com.sanogueralorenzo.androidsteam

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.TextView
import android.widget.Button
import com.sanogueralorenzo.androidsteam.setup.SetupController
import com.sanogueralorenzo.androidsteam.setup.SetupService
import com.sanogueralorenzo.androidsteam.session.SessionActivity

class SetupActivity : Activity() {
    private val setup get() = (application as SteamApplication).setup
    private val observer: (SetupController.State) -> Unit = ::render
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_setup)
        findViewById<View>(R.id.content).setOnApplyWindowInsetsListener { view, insets ->
            val bars = insets.getInsets(android.view.WindowInsets.Type.systemBars())
            val padding = resources.getDimensionPixelSize(R.dimen.screen_padding)
            view.setPadding(padding + bars.left, padding + bars.top, padding + bars.right, padding + bars.bottom)
            insets
        }
        findViewById<TextView>(R.id.device).text = getString(R.string.device_description, Build.MODEL, Build.SOC_MODEL)
        findViewById<Button>(R.id.start_steam).setOnClickListener { startActivity(Intent(this, SessionActivity::class.java)) }
        findViewById<Button>(R.id.action).setOnClickListener {
            when (setup.state) {
                SetupController.State.Missing -> download()
                is SetupController.State.Working -> setup.stop()
                is SetupController.State.Ready -> setup.check()
                is SetupController.State.Failed -> download()
            }
        }
    }

    private fun download() = startForegroundService(Intent(this, SetupService::class.java))

    override fun onStart() { super.onStart(); setup.observe(observer) }
    override fun onStop() { setup.removeObserver(observer); super.onStop() }

    private fun render(state: SetupController.State) {
        val (heading, description, action) = when (state) {
            SetupController.State.Missing -> Triple(R.string.runtime_heading, getString(R.string.runtime_missing), R.string.install_runtime)
            is SetupController.State.Working -> Triple(R.string.runtime_working, state.message, R.string.cancel)
            is SetupController.State.Ready -> Triple(R.string.runtime_ready, state.output.ifBlank { getString(R.string.runtime_test_hint) }, R.string.test_runtime)
            is SetupController.State.Failed -> Triple(R.string.runtime_failed, state.message, R.string.retry)
        }
        findViewById<TextView>(R.id.runtime_heading).setText(heading)
        findViewById<TextView>(R.id.status).text = description
        findViewById<Button>(R.id.action).setText(action)
        findViewById<Button>(R.id.start_steam).isEnabled = state is SetupController.State.Ready
    }
}
