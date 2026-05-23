package com.sanogueralorenzo.voice.summary

import com.sanogueralorenzo.voice.summary.rules.pre.ComposePreLlmRules
import org.junit.Assert.assertEquals
import org.junit.Test

class ComposePreLlmRulesTest {
    private val rules = ComposePreLlmRules()

    @Test
    fun rewrite_appliesIndependentPreLlmRulesInOrder() {
        val result = rules.rewrite("um meet meet me in 5 mins")

        assertEquals("meet me in 5 minutes", result.text)
        assertEquals(
            setOf(
                ComposePreLlmRules.Rule.FILLER,
                ComposePreLlmRules.Rule.ADJACENT_DUPLICATE,
                ComposePreLlmRules.Rule.MINUTES_NORMALIZATION
            ),
            result.appliedRules
        )
    }

    @Test
    fun rewrite_appliesCorrectionTurnBeforeNumberConversion() {
        val result = rules.rewrite("at five, no at six")

        assertEquals("at 6", result.text)
        assertEquals(
            setOf(
                ComposePreLlmRules.Rule.CORRECTION_TURN,
                ComposePreLlmRules.Rule.NUMBER_WORDS_TO_DIGITS
            ),
            result.appliedRules
        )
    }
}
