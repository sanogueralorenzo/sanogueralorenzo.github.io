package com.sanogueralorenzo.voice.audio

import org.junit.Assert.assertEquals
import org.junit.Test

class DictationLanguagesTest {
    @Test
    fun oneLanguageHandlesBothGestures() {
        val languages = DictationLanguages(listOf(DictationLanguage.ENGLISH))

        assertEquals(DictationLanguage.ENGLISH, languages.secondaryOrPrimary)
    }

    @Test
    fun movingSecondLanguageBeforeFirstMakesItPrimary() {
        val languages = DictationLanguages(
            listOf(DictationLanguage.ENGLISH, DictationLanguage.SPANISH)
        ).moveBefore(DictationLanguage.SPANISH, DictationLanguage.ENGLISH)

        assertEquals(
            listOf(DictationLanguage.SPANISH, DictationLanguage.ENGLISH),
            languages.ordered
        )
    }
}
