package com.sanogueralorenzo.voice.keyboard

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class KeyboardSpeechGateTest {
    @Test
    fun waitsForAttackThresholdBeforeStarting() {
        assertFalse(KeyboardSpeechGate.isActive(currentlyActive = false, audioLevel = 0.079f))
        assertTrue(KeyboardSpeechGate.isActive(currentlyActive = false, audioLevel = 0.08f))
    }

    @Test
    fun usesLowerReleaseThresholdAfterStarting() {
        assertTrue(KeyboardSpeechGate.isActive(currentlyActive = true, audioLevel = 0.04f))
        assertFalse(KeyboardSpeechGate.isActive(currentlyActive = true, audioLevel = 0.039f))
    }
}
