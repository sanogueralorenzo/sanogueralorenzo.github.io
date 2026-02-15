package com.sanogueralorenzo.voice.summary

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LiteRtRewritePolicyTest {
    @Test
    fun adaptiveTimeout_usesFreshBudgetForFirstTwoRewrites() {
        val shortText = "hello world"
        assertEquals(3_200L, LiteRtRewritePolicy.adaptiveTimeoutMs(shortText, rewritesSinceEngineInit = 0))
        assertEquals(3_200L, LiteRtRewritePolicy.adaptiveTimeoutMs(shortText, rewritesSinceEngineInit = 1))
    }

    @Test
    fun adaptiveTimeout_dropsToBaseAfterWarmupWindow() {
        val shortText = "hello world"
        assertEquals(2_200L, LiteRtRewritePolicy.adaptiveTimeoutMs(shortText, rewritesSinceEngineInit = 2))
        assertEquals(2_200L, LiteRtRewritePolicy.adaptiveTimeoutMs(shortText, rewritesSinceEngineInit = 7))
    }

    @Test
    fun adaptiveTimeout_addsBonusForLongInputs() {
        val longText = (1..61).joinToString(" ") { "word$it" }
        assertEquals(3_600L, LiteRtRewritePolicy.adaptiveTimeoutMs(longText, rewritesSinceEngineInit = 0))
        assertEquals(2_600L, LiteRtRewritePolicy.adaptiveTimeoutMs(longText, rewritesSinceEngineInit = 5))
    }

    @Test
    fun invalidArgumentDetection_findsKnownSignalInCauseChain() {
        val root = IllegalStateException("INVALID_ARGUMENT: Unprocessed token is null")
        val wrapper = RuntimeException("wrapper", root)
        assertTrue(LiteRtRewritePolicy.isInvalidArgumentError(wrapper))
    }

    @Test
    fun invalidArgumentDetection_ignoresUnrelatedErrors() {
        val error = IllegalArgumentException("Some other runtime failure")
        assertFalse(LiteRtRewritePolicy.isInvalidArgumentError(error))
    }

    @Test
    fun clipCustomInstructions_enforcesRuntimeLimit() {
        val longText = buildString {
            repeat(260) { append('a') }
        }
        val clipped = LiteRtRewritePolicy.clipCustomInstructions(longText)
        assertEquals(220, clipped.length)
    }
}
