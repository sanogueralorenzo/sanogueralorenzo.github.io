package com.sanogueralorenzo.voice.summary

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LiteRtRuntimePolicyTest {
    @Test
    fun invalidArgumentDetection_findsKnownSignalInCauseChain() {
        val root = IllegalStateException("INVALID_ARGUMENT: Unprocessed token is null")
        val wrapper = RuntimeException("wrapper", root)
        assertTrue(LiteRtRuntimePolicy.isInvalidArgumentError(wrapper))
    }

    @Test
    fun invalidArgumentDetection_ignoresUnrelatedErrors() {
        val error = IllegalArgumentException("Some other runtime failure")
        assertFalse(LiteRtRuntimePolicy.isInvalidArgumentError(error))
    }

    @Test
    fun inputTooLongDetection_matchesKnownSignals() {
        val root = IllegalStateException("Input token ids are too long")
        val wrapper = RuntimeException("wrapper", root)
        assertTrue(LiteRtRuntimePolicy.isInputTooLongError(wrapper))
    }

    @Test
    fun inputTooLongDetection_ignoresUnrelatedErrors() {
        val error = IllegalArgumentException("network timeout")
        assertFalse(LiteRtRuntimePolicy.isInputTooLongError(error))
    }
}
