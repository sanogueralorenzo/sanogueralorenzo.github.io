package com.sanogueralorenzo.voice.product

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceHomeStateTest {
    @Test
    fun readyRequiresEveryProductRequirement() {
        assertTrue(
            VoiceHomeState(
                modelsReady = true,
                microphoneAllowed = true,
                voiceServiceEnabled = true
            ).ready
        )
        assertFalse(
            VoiceHomeState(
                modelsReady = true,
                microphoneAllowed = true,
                voiceServiceEnabled = false
            ).ready
        )
    }
}
