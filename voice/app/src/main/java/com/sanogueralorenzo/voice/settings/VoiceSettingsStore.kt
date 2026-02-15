package com.sanogueralorenzo.voice.settings

import android.content.Context

/**
 * App-level persisted settings shared by setup UI and IME runtime.
 */
class VoiceSettingsStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun isLiteRtRewriteEnabled(): Boolean {
        return prefs.getBoolean(KEY_LITERT_REWRITE_ENABLED, DEFAULT_LITERT_REWRITE_ENABLED)
    }

    fun setLiteRtRewriteEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_LITERT_REWRITE_ENABLED, enabled).apply()
    }

    fun customInstructions(): String {
        return prefs.getString(KEY_CUSTOM_INSTRUCTIONS, "")?.trim().orEmpty()
    }

    fun setCustomInstructions(value: String) {
        val normalized = value
            .replace("\r\n", "\n")
            .trim()
            .take(MAX_CUSTOM_INSTRUCTIONS_CHARS)
        prefs.edit().putString(KEY_CUSTOM_INSTRUCTIONS, normalized).apply()
    }

    companion object {
        private const val PREFS_NAME = "voice_settings"
        private const val KEY_LITERT_REWRITE_ENABLED = "litert_rewrite_enabled"
        private const val KEY_CUSTOM_INSTRUCTIONS = "custom_instructions"
        private const val DEFAULT_LITERT_REWRITE_ENABLED = true
        const val MAX_CUSTOM_INSTRUCTIONS_CHARS = 600
    }
}
