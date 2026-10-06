package com.sanogueralorenzo.androidsteam.games

import android.app.Activity
import android.app.AlertDialog
import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast
import android.widget.Button
import com.sanogueralorenzo.androidsteam.R
import com.sanogueralorenzo.androidsteam.input.ControlProfile
import com.sanogueralorenzo.androidsteam.input.TouchKey
import com.sanogueralorenzo.androidsteam.library.SteamLibrary

/** A pre-launch editor; Steam still owns installations and execution. */
class GameSettingsActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val appId = intent.getIntExtra("appId", 0)
            val game = SteamLibrary(this).read().games.find { it.appId == appId }
            require(game != null) { "Refresh the library for the selected account before editing game settings." }
            edit(game.metadata)
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
            val extra = TouchKey.load(this, game.appId).toMutableList()
            val extraButton = content.findViewById<Button>(R.id.extra_keys)
            fun labelKeys() { extraButton.text = "Extra touch keys: " + extra.joinToString { it.label }.ifEmpty { "None" } }
            labelKeys()
            controls.onItemSelectedListener = object : android.widget.AdapterView.OnItemSelectedListener {
                override fun onNothingSelected(parent: android.widget.AdapterView<*>?) = Unit
                override fun onItemSelected(parent: android.widget.AdapterView<*>?, view: android.view.View?, position: Int, id: Long) {
                    extraButton.visibility = if (ControlProfile.entries[position] in listOf(ControlProfile.ARROWS, ControlProfile.WASD)) android.view.View.VISIBLE else android.view.View.GONE
                }
            }
            extraButton.setOnClickListener {
                val selected = extra.toMutableList()
                AlertDialog.Builder(this).setTitle("Choose up to four extra keys")
                    .setMultiChoiceItems(TouchKey.entries.map { it.label }.toTypedArray(), TouchKey.entries.map { it in selected }.toBooleanArray()) { picker, index, checked ->
                        val key = TouchKey.entries[index]
                        if (checked && selected.size == 4) {
                            (picker as AlertDialog).listView.setItemChecked(index, false)
                            message("Choose at most four extra keys.")
                        } else if (checked) selected += key else selected -= key
                    }.setPositiveButton("Apply") { _, _ -> extra.clear(); extra += selected; labelKeys() }
                    .setNegativeButton(R.string.cancel, null).show()
            }
            val dialog = AlertDialog.Builder(this).setTitle(game.name).setView(content)
                .setPositiveButton("Save", null).setNegativeButton(R.string.cancel) { _, _ -> finish() }
                .setOnCancelListener { finish() }.create()
            dialog.setOnShowListener {
                dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                    try {
                        profiles.save(game.appId, GameLaunchProfile(tools[tool.selectedItemPosition],
                            GameLaunchProfile.words(arguments.text.toString()), GameLaunchProfile.environment(environment.text.toString())))
                        ControlProfile.save(this, game.appId, ControlProfile.entries[controls.selectedItemPosition])
                        TouchKey.save(this, game.appId, extra)
                        message("Saved. Updated launch settings apply before your next game launch.")
                        dialog.dismiss(); finish()
                    } catch (failure: Exception) { message(failure.message ?: "Cannot save game settings.") }
                }
            }
            dialog.show()
        } catch (failure: Exception) { message(failure.message ?: "Game settings could not load."); finish() }
    }

    private fun message(text: String) = Toast.makeText(this, text, Toast.LENGTH_LONG).show()
}
