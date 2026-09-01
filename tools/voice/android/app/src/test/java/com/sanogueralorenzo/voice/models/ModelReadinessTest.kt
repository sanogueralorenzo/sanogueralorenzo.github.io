package com.sanogueralorenzo.voice.models

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelReadinessTest {
    @Test
    fun allReadyRequiresEveryRuntimeAsset() {
        assertTrue(
            ModelReadiness(
                liteRtReady = true,
                moonshineReady = true,
                promptReady = true,
                promptVersion = "2026-09-01"
            ).allReady
        )
        assertFalse(
            ModelReadiness(
                liteRtReady = true,
                moonshineReady = true,
                promptReady = false,
                promptVersion = null
            ).allReady
        )
    }
}
