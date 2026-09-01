package com.sanogueralorenzo.voice.audio

import org.junit.Assert.assertEquals
import org.junit.Test

class DictationLanguagesTest {
    @Test
    fun enablingSecondLanguageAddsItAsLongPress() {
        val languages = DictationLanguages(listOf(DictationLanguage.ENGLISH))
            .withEnabled(DictationLanguage.SPANISH, enabled = true)

        assertEquals(
            listOf(DictationLanguage.ENGLISH, DictationLanguage.SPANISH),
            languages.ordered
        )
        assertEquals(DictationLanguage.SPANISH, languages.secondaryOrPrimary)
    }

    @Test
    fun disablingLastLanguageIsIgnored() {
        val languages = DictationLanguages(listOf(DictationLanguage.ENGLISH))
            .withEnabled(DictationLanguage.ENGLISH, enabled = false)

        assertEquals(listOf(DictationLanguage.ENGLISH), languages.ordered)
        assertEquals(DictationLanguage.ENGLISH, languages.secondaryOrPrimary)
    }

    @Test
    fun movingSecondLanguageEarlierMakesItPrimary() {
        val languages = DictationLanguages(
            listOf(DictationLanguage.ENGLISH, DictationLanguage.SPANISH)
        ).move(DictationLanguage.SPANISH, offset = -1)

        assertEquals(
            listOf(DictationLanguage.SPANISH, DictationLanguage.ENGLISH),
            languages.ordered
        )
    }
}
