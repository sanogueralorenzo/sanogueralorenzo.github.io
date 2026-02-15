package com.sanogueralorenzo.voice.summary

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LiteRtSafetyGateTest {
    @Test
    fun rejectsOutOfContextFillerAdditions() {
        val source = "Can you send the report by 5 pm today"
        val rewritten = "Can you send the report by 5 pm today? Let me know, thanks!"

        assertFalse(
            LiteRtSafetyGate.isSafeRewrite(
                source = source,
                rewritten = rewritten,
                allowStyleNovelty = false
            )
        )
    }

    @Test
    fun acceptsConservativeRewriteWithoutAddedContext() {
        val source = "um I think we should meet tomorrow at 3 and review the budget"
        val rewritten = "I think we should meet tomorrow at 3 and review the budget."

        assertTrue(
            LiteRtSafetyGate.isSafeRewrite(
                source = source,
                rewritten = rewritten,
                allowStyleNovelty = false
            )
        )
    }

    @Test
    fun preservesListLikeContentWhenRewrittenAsBullets() {
        val source = "buy milk, eggs, bananas, bread"
        val rewritten = "- buy milk\n- eggs\n- bananas\n- bread"

        assertTrue(
            LiteRtSafetyGate.isSafeRewrite(
                source = source,
                rewritten = rewritten,
                allowStyleNovelty = false
            )
        )
    }

    @Test
    fun rejectsMissingNumbersLinksOrNegation() {
        val source = "Do not send before 4 pm. Use https://example.com/task/42"
        val missingNegation = "Send before 4 pm. Use https://example.com/task/42"
        val missingLink = "Do not send before 4 pm. Use the task page"

        assertFalse(
            LiteRtSafetyGate.isSafeRewrite(
                source = source,
                rewritten = missingNegation,
                allowStyleNovelty = false
            )
        )
        assertFalse(
            LiteRtSafetyGate.isSafeRewrite(
                source = source,
                rewritten = missingLink,
                allowStyleNovelty = false
            )
        )
    }
}
