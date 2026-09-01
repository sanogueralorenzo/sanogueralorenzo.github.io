package com.sanogueralorenzo.voice.models

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelReadinessTest {
    @Test
    fun allReadyReflectsMoonshineAssets() {
        assertTrue(ModelReadiness(moonshineReady = true).allReady)
        assertFalse(ModelReadiness(moonshineReady = false).allReady)
    }
}
