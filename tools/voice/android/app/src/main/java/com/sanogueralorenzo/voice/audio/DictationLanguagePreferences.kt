package com.sanogueralorenzo.voice.audio

import android.content.Context

data class DictationLanguages(
    val ordered: List<DictationLanguage>
) {
    init {
        require(ordered.isNotEmpty()) { "At least one language must be enabled." }
        require(ordered.distinct().size == ordered.size) { "Languages must be unique." }
    }

    val primary: DictationLanguage
        get() = ordered.first()

    val secondaryOrPrimary: DictationLanguage
        get() = ordered.getOrElse(1) { primary }

    fun isEnabled(language: DictationLanguage): Boolean = language in ordered

    fun withEnabled(language: DictationLanguage, enabled: Boolean): DictationLanguages {
        if (enabled && !isEnabled(language)) {
            return DictationLanguages(ordered + language)
        }
        if (!enabled && isEnabled(language) && ordered.size > 1) {
            return DictationLanguages(ordered - language)
        }
        return this
    }

    fun move(language: DictationLanguage, offset: Int): DictationLanguages {
        val fromIndex = ordered.indexOf(language)
        if (fromIndex == -1) return this
        val toIndex = (fromIndex + offset).coerceIn(0, ordered.lastIndex)
        if (fromIndex == toIndex) return this
        val reordered = ordered.toMutableList()
        reordered.removeAt(fromIndex)
        reordered.add(toIndex, language)
        return DictationLanguages(reordered)
    }
}

/** Persists the enabled languages in tap/long-press priority order. */
class DictationLanguagePreferences(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE
    )

    fun read(): DictationLanguages {
        val ordered = preferences.getString(KEY_ORDERED, null)
            ?.split(',')
            ?.mapNotNull(::languageFromStorageValue)
            ?.distinct()
            .orEmpty()
        return if (ordered.isEmpty()) DEFAULT_LANGUAGES else DictationLanguages(ordered)
    }

    fun primary(): DictationLanguage = read().primary

    fun secondaryOrPrimary(): DictationLanguage = read().secondaryOrPrimary

    fun setEnabled(language: DictationLanguage, enabled: Boolean): DictationLanguages {
        return write(read().withEnabled(language, enabled))
    }

    fun moveEarlier(language: DictationLanguage): DictationLanguages {
        return write(read().move(language, -1))
    }

    fun moveLater(language: DictationLanguage): DictationLanguages {
        return write(read().move(language, 1))
    }

    private fun write(languages: DictationLanguages): DictationLanguages {
        preferences.edit()
            .putString(KEY_ORDERED, languages.ordered.joinToString(",") { it.storageValue })
            .apply()
        return languages
    }

    private fun languageFromStorageValue(value: String): DictationLanguage? {
        return DictationLanguage.entries.firstOrNull { it.storageValue == value }
    }

    private val DictationLanguage.storageValue: String
        get() = when (this) {
            DictationLanguage.ENGLISH -> "en"
            DictationLanguage.SPANISH -> "es"
        }

    private companion object {
        private const val PREFERENCES_NAME = "dictation_languages"
        private const val KEY_ORDERED = "ordered"
        private val DEFAULT_LANGUAGES = DictationLanguages(
            ordered = listOf(DictationLanguage.ENGLISH)
        )
    }
}
