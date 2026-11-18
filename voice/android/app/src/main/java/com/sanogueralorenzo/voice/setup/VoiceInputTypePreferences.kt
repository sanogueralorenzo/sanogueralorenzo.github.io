package com.sanogueralorenzo.voice.setup

import android.content.Context
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn

enum class VoiceInputType {
    KEYBOARD,
    OVERLAY
}

/** Owns the user's explicit choice between the Voice keyboard and floating overlay. */
@Inject
@SingleIn(AppScope::class)
class VoiceInputTypePreferences(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE
    )

    fun read(): VoiceInputType? {
        return when (preferences.getString(KEY_INPUT_TYPE, null)) {
            KEYBOARD_VALUE -> VoiceInputType.KEYBOARD
            OVERLAY_VALUE -> VoiceInputType.OVERLAY
            else -> null
        }
    }

    fun write(inputType: VoiceInputType) {
        val value = when (inputType) {
            VoiceInputType.KEYBOARD -> KEYBOARD_VALUE
            VoiceInputType.OVERLAY -> OVERLAY_VALUE
        }
        preferences.edit().putString(KEY_INPUT_TYPE, value).apply()
    }

    private companion object {
        private const val PREFERENCES_NAME = "voice_input_type"
        private const val KEY_INPUT_TYPE = "input_type"
        private const val KEYBOARD_VALUE = "keyboard"
        private const val OVERLAY_VALUE = "overlay"
    }
}
