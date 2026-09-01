package com.sanogueralorenzo.voice.audio

import android.content.Context

data class DictationLanguages(
    val primary: DictationLanguage,
    val secondary: DictationLanguage
) {
    init {
        require(primary != secondary) { "Primary and secondary languages must differ." }
    }

    fun withPrimary(language: DictationLanguage): DictationLanguages {
        return if (language == secondary) {
            DictationLanguages(primary = language, secondary = primary)
        } else {
            copy(primary = language)
        }
    }

    fun withSecondary(language: DictationLanguage): DictationLanguages {
        return if (language == primary) {
            DictationLanguages(primary = secondary, secondary = language)
        } else {
            copy(secondary = language)
        }
    }
}

/** Persists the language assigned to tap and long-press for both dictation products. */
class DictationLanguagePreferences(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE
    )

    fun read(): DictationLanguages {
        val primary = readLanguage(KEY_PRIMARY) ?: DEFAULT_LANGUAGES.primary
        val secondary = readLanguage(KEY_SECONDARY) ?: DEFAULT_LANGUAGES.secondary
        return if (primary == secondary) DEFAULT_LANGUAGES else DictationLanguages(primary, secondary)
    }

    fun primary(): DictationLanguage = read().primary

    fun secondary(): DictationLanguage = read().secondary

    fun setPrimary(language: DictationLanguage): DictationLanguages {
        return write(read().withPrimary(language))
    }

    fun setSecondary(language: DictationLanguage): DictationLanguages {
        return write(read().withSecondary(language))
    }

    private fun write(languages: DictationLanguages): DictationLanguages {
        preferences.edit()
            .putString(KEY_PRIMARY, languages.primary.storageValue)
            .putString(KEY_SECONDARY, languages.secondary.storageValue)
            .apply()
        return languages
    }

    private fun readLanguage(key: String): DictationLanguage? {
        val stored = preferences.getString(key, null) ?: return null
        return DictationLanguage.entries.firstOrNull { it.storageValue == stored }
    }

    private val DictationLanguage.storageValue: String
        get() = when (this) {
            DictationLanguage.ENGLISH -> "en"
            DictationLanguage.SPANISH -> "es"
        }

    private companion object {
        private const val PREFERENCES_NAME = "dictation_languages"
        private const val KEY_PRIMARY = "primary"
        private const val KEY_SECONDARY = "secondary"
        private val DEFAULT_LANGUAGES = DictationLanguages(
            primary = DictationLanguage.ENGLISH,
            secondary = DictationLanguage.SPANISH
        )
    }
}
