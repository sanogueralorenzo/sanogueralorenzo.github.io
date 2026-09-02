package com.sanogueralorenzo.voice.audio

import android.content.Context
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn

data class DictationLanguages(
    val ordered: List<DictationLanguage>
) {
    init {
        require(ordered.isNotEmpty()) { "At least one language must be ordered." }
        require(ordered.distinct().size == ordered.size) { "Languages must be unique." }
    }

    val primary: DictationLanguage
        get() = ordered.first()

    val secondaryOrPrimary: DictationLanguage
        get() = ordered.getOrElse(1) { primary }

    fun swap(first: DictationLanguage, second: DictationLanguage): DictationLanguages {
        val firstIndex = ordered.indexOf(first)
        val secondIndex = ordered.indexOf(second)
        if (firstIndex == -1 || secondIndex == -1 || firstIndex == secondIndex) return this
        val reordered = ordered.toMutableList()
        reordered[firstIndex] = second
        reordered[secondIndex] = first
        return DictationLanguages(reordered)
    }
}

/** Persists downloaded languages in tap/long-press priority order. */
@Inject
@SingleIn(AppScope::class)
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

    fun syncDownloaded(downloaded: Set<DictationLanguage>): List<DictationLanguage> {
        if (downloaded.isEmpty()) return emptyList()
        val existingOrder = read().ordered.filter(downloaded::contains)
        val missing = DictationLanguage.entries.filter { it in downloaded && it !in existingOrder }
        return write(DictationLanguages(existingOrder + missing)).ordered
    }

    fun swap(
        first: DictationLanguage,
        second: DictationLanguage
    ): DictationLanguages {
        return write(read().swap(first, second))
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
