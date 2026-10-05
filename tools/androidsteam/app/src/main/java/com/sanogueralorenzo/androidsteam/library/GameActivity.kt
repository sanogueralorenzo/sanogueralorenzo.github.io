package com.sanogueralorenzo.androidsteam.library

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.text.format.DateUtils
import android.text.format.Formatter
import android.view.View
import android.view.WindowInsets
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import com.sanogueralorenzo.androidsteam.R
import com.sanogueralorenzo.androidsteam.SteamApplication
import com.sanogueralorenzo.androidsteam.games.GameProfiles
import com.sanogueralorenzo.androidsteam.games.GameSettingsActivity
import com.sanogueralorenzo.androidsteam.input.ControlProfile
import com.sanogueralorenzo.androidsteam.session.SessionActivity

class GameActivity : Activity() {
    private val app get() = application as SteamApplication
    private val appId get() = intent.getIntExtra("appId", 0)
    private var game: LibraryGame? = null
    private val observer: (LibraryController.State) -> Unit = ::render
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (appId <= 0) { finish(); return }
        setContentView(R.layout.activity_game)
        findViewById<View>(R.id.game_screen).setOnApplyWindowInsetsListener { view, insets ->
            val bars = insets.getInsets(WindowInsets.Type.systemBars())
            view.setPadding(bars.left, bars.top, bars.right, bars.bottom)
            insets
        }
        findViewById<View>(R.id.game_back).setOnClickListener { finish() }
        findViewById<View>(R.id.detail_play).setOnClickListener {
            val selected = game ?: return@setOnClickListener
            if (app.session.gameAppId != null && app.session.gameAppId != appId) {
                Toast.makeText(this, "Another game is running. Close it in Steam before starting this game.", Toast.LENGTH_LONG).show()
                openSteam()
            } else startActivity(SessionActivity.intent(this).putExtra("appId", appId)
                .putExtra("install", !selected.installed))
        }
        findViewById<View>(R.id.detail_manage).setOnClickListener { openSteam() }
        findViewById<View>(R.id.detail_settings).setOnClickListener {
            startActivity(Intent(this, GameSettingsActivity::class.java).putExtra("appId", appId))
        }
        listOf(R.id.tab_library, R.id.tab_search, R.id.tab_downloads).forEachIndexed { index, id ->
            findViewById<View>(id).setOnClickListener {
                startActivity(Intent(this, com.sanogueralorenzo.androidsteam.MainActivity::class.java)
                    .putExtra("tab", index).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
            }
        }
    }
    override fun onStart() { super.onStart(); app.library.observe(observer) }
    override fun onStop() { app.library.removeObserver(observer); super.onStop() }
    private fun openSteam() = startActivity(SessionActivity.intent(this))
    private fun render(state: LibraryController.State) {
        game = state.snapshot?.games?.find { it.appId == appId }
        val selected = game
        findViewById<TextView>(R.id.detail_error).text = state.error ?: if (selected == null) "This game is unavailable for the selected account. Return to the library and refresh." else "Cloud status and achievements are available in Steam."
        findViewById<View>(R.id.detail_play).isEnabled = selected != null
        findViewById<View>(R.id.detail_settings).isEnabled = selected != null
        if (selected == null) return
        findViewById<TextView>(R.id.detail_name).text = selected.name
        findViewById<TextView>(R.id.detail_state).text = when {
            selected.pending -> "Download or update pending in Steam"
            selected.installed -> "Installed · ${Formatter.formatShortFileSize(this, selected.size)}"
            else -> "Available license · Not installed"
        }
        findViewById<Button>(R.id.detail_play).apply {
            setText(if (selected.installed) R.string.play else R.string.install_game)
            isEnabled = !selected.pending
        }
        findViewById<TextView>(R.id.detail_history).text = listOfNotNull(
            selected.lastPlayed?.let { "Last played · ${DateUtils.getRelativeTimeSpanString(it * 1000)}" },
            selected.playtimeMinutes?.let { "Play time · ${it / 60}h ${it % 60}m" }
        ).joinToString("\n").ifEmpty { "Steam has no cached play history for this game." }
        val profile = runCatching { GameProfiles(this).load(appId) }
        findViewById<TextView>(R.id.detail_compatibility).text = profile.fold({ value ->
            val tool = when (value.tool) { "androidsteam-proton" -> "Android Steam Proton (ARM64)"; null -> "Steam default (unverified)"; "" -> "Native Linux (unverified)"; else -> "Steam selection: ${value.tool}" }
            "$tool\n${ControlProfile.load(this, appId).label}\nListed builds: ${selected.metadata.platforms.joinToString(", ")}\nGame compatibility depends on its build and launch settings." +
                selected.metadata.controllerSupport?.let { "\nSteam lists $it controller support; Android controller compatibility is unverified." }.orEmpty()
        }, { it.message ?: "Open Steam to prepare game settings." })
        app.artwork.show(findViewById<ImageView>(R.id.game_hero), selected)
    }
}
