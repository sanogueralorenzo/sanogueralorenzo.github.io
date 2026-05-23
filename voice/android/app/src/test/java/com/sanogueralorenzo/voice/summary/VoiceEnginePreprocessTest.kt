package com.sanogueralorenzo.voice.summary

import com.sanogueralorenzo.voice.engine.VoiceEngine
import org.junit.Assert.assertEquals
import org.junit.Test

class VoiceEnginePreprocessTest {
    @Test
    fun preprocess_appliesIndependentPreLlmRulesInOrder() {
        val result = VoiceEngine.preprocess("um meet meet me in 5 mins")

        assertEquals("meet me in 5 minutes", result.text)
        assertEquals(
            setOf(
                "FILLER",
                "ADJACENT_DUPLICATE",
                "MINUTES_NORMALIZATION"
            ),
            result.appliedRuleIds
        )
    }

    @Test
    fun preprocess_appliesCorrectionTurnBeforeNumberConversion() {
        val result = VoiceEngine.preprocess("at five, no at six")

        assertEquals("at 6", result.text)
        assertEquals(
            setOf(
                "CORRECTION_TURN",
                "NUMBER_WORDS_TO_DIGITS"
            ),
            result.appliedRuleIds
        )
    }
}
