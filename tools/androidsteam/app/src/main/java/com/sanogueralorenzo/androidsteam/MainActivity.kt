package com.sanogueralorenzo.androidsteam

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.View
import android.widget.TextView
import android.widget.Button
import com.sanogueralorenzo.androidsteam.runtime.RuntimeController
import com.sanogueralorenzo.androidsteam.session.SessionActivity
import com.sanogueralorenzo.androidsteam.games.GameSettingsActivity

class MainActivity : Activity() {
    private val runtime get() = (application as SteamApplication).runtime
    private val observer: (RuntimeController.State) -> Unit = ::render
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        findViewById<View>(R.id.content).setOnApplyWindowInsetsListener { view, insets ->
            val bars = insets.getInsets(android.view.WindowInsets.Type.systemBars())
            val padding = resources.getDimensionPixelSize(R.dimen.screen_padding)
            view.setPadding(padding + bars.left, padding + bars.top, padding + bars.right, padding + bars.bottom)
            insets
        }
        findViewById<TextView>(R.id.device).text = getString(R.string.device_description, Build.MODEL, Build.SOC_MODEL)
        findViewById<Button>(R.id.start_steam).setOnClickListener { startActivity(Intent(this, SessionActivity::class.java)) }
        findViewById<Button>(R.id.game_settings).setOnClickListener { startActivity(Intent(this, GameSettingsActivity::class.java)) }
        findViewById<Button>(R.id.action).setOnClickListener {
            when (val state = runtime.state) {
                RuntimeController.State.Missing -> runtime.install()
                is RuntimeController.State.Working -> runtime.stop()
                is RuntimeController.State.Ready -> runtime.check()
                is RuntimeController.State.Failed -> if (state.installed) runtime.check() else runtime.install()
            }
        }
    }

    override fun onStart() { super.onStart(); runtime.observe(observer) }
    override fun onStop() { runtime.removeObserver(observer); super.onStop() }

    private fun render(state: RuntimeController.State) {
        val (heading, description, action) = when (state) {
            RuntimeController.State.Missing -> Triple(R.string.runtime_heading, getString(R.string.runtime_missing), R.string.install_runtime)
            is RuntimeController.State.Working -> Triple(R.string.runtime_working, state.message, R.string.cancel)
            is RuntimeController.State.Ready -> Triple(R.string.runtime_ready, state.output.ifBlank { getString(R.string.runtime_test_hint) }, R.string.test_runtime)
            is RuntimeController.State.Failed -> Triple(R.string.runtime_failed, state.message, R.string.retry)
        }
        findViewById<TextView>(R.id.runtime_heading).setText(heading)
        findViewById<TextView>(R.id.status).text = description
        findViewById<Button>(R.id.action).setText(action)
        findViewById<Button>(R.id.start_steam).isEnabled = state is RuntimeController.State.Ready
    }
}
