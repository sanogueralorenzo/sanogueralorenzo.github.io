package com.sanogueralorenzo.androidsteam.games

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import com.sanogueralorenzo.androidsteam.R
import com.sanogueralorenzo.androidsteam.input.ControlProfile
import java.io.File

/** A pre-launch editor; Steam still owns installations and execution. */
class GameSettingsActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        chooseGame()
    }

    private fun chooseGame() {
        try {
            val root = File(filesDir, "home/.local/share/Steam")
            val metadata = SteamAppInfo.games(File(root, "appcache/appinfo.vdf"))
            val games = File(root, "steamapps").listFiles().orEmpty().filter { it.name.startsWith("appmanifest_") && it.extension == "acf" && it.length() <= 65_536 }
                .mapNotNull { file ->
                    val manifest = SteamSettingsText(file.readText())
                    val flags = manifest.get(listOf("AppState", "StateFlags"))?.toIntOrNull() ?: 0
                    val appId = manifest.get(listOf("AppState", "appid"))?.toIntOrNull()
                    if (flags and 4 != 0) metadata[appId] else null
                }.sortedBy { it.name.lowercase() }
            if (games.isEmpty()) { message("Install a game in Steam before editing its settings."); finish(); return }
            AlertDialog.Builder(this).setTitle("Installed games")
                .setItems(games.map { it.name }.toTypedArray()) { _, index -> edit(games[index]) }
                .setNegativeButton(R.string.cancel) { _, _ -> finish() }.setOnCancelListener { finish() }.show()
        } catch (failure: Exception) { message(failure.message ?: "Game settings could not load."); finish() }
    }

    private fun edit(game: SteamGameMetadata) {
        try {
            val profiles = GameProfiles(this)
            val profile = profiles.load(game.appId)
            val content = layoutInflater.inflate(R.layout.game_settings, null)
            content.findViewById<TextView>(R.id.platforms).text = if ("linux" in game.platforms && "windows" in game.platforms)
                "A Linux build is listed; its native Android execution path is unverified. ARM64 Proton runs the Windows build."
            else if ("linux" in game.platforms) "A Linux build is listed; its native Android execution path is unverified."
            else if ("windows" in game.platforms) "This game lists a Windows build, which needs Proton."
            else "The execution path for this game's listed build is unverified."
            val tools = mutableListOf<String?>(null)
            if ("windows" in game.platforms) tools += "androidsteam-proton"
            if (profile.tool != null && profile.tool !in tools) tools += profile.tool
            val tool = content.findViewById<Spinner>(R.id.compatibility)
            tool.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, tools.map {
                when (it) { null -> "Steam default (unverified)"; "androidsteam-proton" -> "Android Steam Proton (ARM64)"; "" -> "Native Linux (unverified)"; else -> "Steam selection: $it" }
            })
            tool.setSelection(tools.indexOf(profile.tool))
            val arguments = content.findViewById<EditText>(R.id.arguments)
            arguments.setText(GameLaunchProfile.argumentText(profile.arguments))
            val environment = content.findViewById<EditText>(R.id.environment)
            environment.setText(profile.environment.entries.joinToString("\n") { "${it.key}=${it.value}" })
            val controls = content.findViewById<Spinner>(R.id.controls)
            controls.adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, ControlProfile.entries.map { it.label })
            controls.setSelection(ControlProfile.load(this, game.appId).ordinal)
            val dialog = AlertDialog.Builder(this).setTitle(game.name).setView(content)
                .setPositiveButton("Save", null).setNegativeButton(R.string.cancel) { _, _ -> finish() }
                .setOnCancelListener { finish() }.create()
            dialog.setOnShowListener {
                dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                    try {
                        profiles.save(game.appId, GameLaunchProfile(tools[tool.selectedItemPosition],
                            GameLaunchProfile.words(arguments.text.toString()), GameLaunchProfile.environment(environment.text.toString())))
                        ControlProfile.save(this, game.appId, ControlProfile.entries[controls.selectedItemPosition])
                        message("Saved. Launch settings apply the next time Steam starts.")
                        dialog.dismiss(); finish()
                    } catch (failure: Exception) { message(failure.message ?: "Cannot save game settings.") }
                }
            }
            dialog.show()
        } catch (failure: Exception) { message(failure.message ?: "Game settings could not load."); finish() }
    }

    private fun message(text: String) = Toast.makeText(this, text, Toast.LENGTH_LONG).show()
}
