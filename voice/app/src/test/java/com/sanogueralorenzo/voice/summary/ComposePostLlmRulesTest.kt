package com.sanogueralorenzo.voice.summary

import org.junit.Assert.assertEquals
import org.junit.Test

class ComposePostLlmRulesTest {
    private val policy = ComposePostLlmRules()

    @Test
    fun cleanModelOutput_capitalizesStartAndAfterConfiguredPunctuation() {
        val cleaned = policy.cleanModelOutput(
            text = "hey mia, can you buy apples. actually get milk? thanks",
            bulletMode = false
        )

        assertEquals("Hey mia, can you buy apples. Actually get milk? Thanks", cleaned)
    }

    @Test
    fun cleanModelOutput_appliesCapitalizationAfterLabelCleanup() {
        val cleaned = policy.cleanModelOutput(
            text = "cleaned: hello, this is fine. maybe? yes",
            bulletMode = false
        )

        assertEquals("Hello, this is fine. Maybe? Yes", cleaned)
    }

    @Test
    fun cleanModelOutput_flattensBulletsAndCapitalizesResult() {
        val cleaned = policy.cleanModelOutput(
            text = "- apple\n- milk\n- avocado",
            bulletMode = false
        )

        assertEquals("Apple milk avocado", cleaned)
    }

    @Test
    fun cleanModelOutput_convertsSpokenDigitSequenceWithCommasToNumber() {
        val cleaned = policy.cleanModelOutput(
            text = "the code is one, two, three",
            bulletMode = false
        )

        assertEquals("The code is 123", cleaned)
    }

    @Test
    fun cleanModelOutput_convertsSpokenDigitSequenceWithoutCommasToNumber() {
        val cleaned = policy.cleanModelOutput(
            text = "call one two three four five",
            bulletMode = false
        )

        assertEquals("Call 12345", cleaned)
    }

    @Test
    fun cleanModelOutput_convertsSpokenCardinalNumberToNumber() {
        val cleaned = policy.cleanModelOutput(
            text = "set it to three hundred twenty one",
            bulletMode = false
        )

        assertEquals("Set it to 321", cleaned)
    }
}
