package com.sanogueralorenzo.voice.dictation

import org.junit.Assert.assertEquals
import org.junit.Test

class DictationLanguagesTest {
    @Test
    fun oneLanguageHandlesBothGestures() {
        val languages = DictationLanguages(listOf(DictationLanguage.ENGLISH))

        assertEquals(DictationLanguage.ENGLISH, languages.secondaryOrPrimary)
    }

    @Test
    fun droppingEitherLanguageOnTheOtherSwapsTheirOrder() {
        val initial = DictationLanguages(
            listOf(DictationLanguage.ENGLISH, DictationLanguage.SPANISH)
        )
        val englishDroppedOnSpanish = initial.swap(
            DictationLanguage.ENGLISH,
            DictationLanguage.SPANISH
        )
        val spanishDroppedOnEnglish = initial.swap(
            DictationLanguage.SPANISH,
            DictationLanguage.ENGLISH
        )

        assertEquals(
            listOf(DictationLanguage.SPANISH, DictationLanguage.ENGLISH),
            englishDroppedOnSpanish.ordered
        )
        assertEquals(
            listOf(DictationLanguage.SPANISH, DictationLanguage.ENGLISH),
            spanishDroppedOnEnglish.ordered
        )
    }

    @Test
    fun swappingReversedLanguagesRestoresOriginalOrder() {
        val languages = DictationLanguages(
            listOf(DictationLanguage.SPANISH, DictationLanguage.ENGLISH)
        ).swap(DictationLanguage.ENGLISH, DictationLanguage.SPANISH)

        assertEquals(
            listOf(DictationLanguage.ENGLISH, DictationLanguage.SPANISH),
            languages.ordered
        )
    }
}
