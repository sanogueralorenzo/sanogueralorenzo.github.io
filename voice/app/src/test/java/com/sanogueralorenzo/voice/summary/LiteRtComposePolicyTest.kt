package com.sanogueralorenzo.voice.summary

import org.junit.Assert.assertEquals
import org.junit.Test

class LiteRtComposePolicyTest {
    private val policy = LiteRtComposePolicy()

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
}
