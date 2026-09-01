package com.sanogueralorenzo.voice.audio

import org.junit.Assert.assertEquals
import org.junit.Test

class DictationLanguagesTest {
    private val defaults = DictationLanguages(
        primary = DictationLanguage.ENGLISH,
        secondary = DictationLanguage.SPANISH
    )

    @Test
    fun selectingCurrentSecondaryAsPrimarySwapsLanguages() {
        assertEquals(
            DictationLanguages(
                primary = DictationLanguage.SPANISH,
                secondary = DictationLanguage.ENGLISH
            ),
            defaults.withPrimary(DictationLanguage.SPANISH)
        )
    }

    @Test
    fun selectingCurrentPrimaryAsSecondarySwapsLanguages() {
        assertEquals(
            DictationLanguages(
                primary = DictationLanguage.SPANISH,
                secondary = DictationLanguage.ENGLISH
            ),
            defaults.withSecondary(DictationLanguage.ENGLISH)
        )
    }
}
