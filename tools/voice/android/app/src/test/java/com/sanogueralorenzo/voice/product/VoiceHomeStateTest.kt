package com.sanogueralorenzo.voice.product

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceHomeStateTest {
    @Test
    fun keyboardReadyRequiresSelectedVoiceKeyboard() {
        assertTrue(
            VoiceHomeState(
                modelsReady = true,
                microphoneAllowed = true,
                voiceKeyboardSelected = true,
                inputType = VoiceInputType.KEYBOARD
            ).ready
        )
        assertFalse(
            VoiceHomeState(
                modelsReady = true,
                microphoneAllowed = true,
                voiceServiceEnabled = true,
                inputType = VoiceInputType.KEYBOARD
            ).ready
        )
    }

    @Test
    fun overlayReadyRequiresVoiceService() {
        assertTrue(
            VoiceHomeState(
                modelsReady = true,
                microphoneAllowed = true,
                voiceServiceEnabled = true,
                inputType = VoiceInputType.OVERLAY
            ).ready
        )
        assertFalse(
            VoiceHomeState(
                modelsReady = true,
                microphoneAllowed = true,
                voiceKeyboardSelected = true,
                inputType = VoiceInputType.OVERLAY
            ).ready
        )
    }

    @Test
    fun readyRequiresAnExplicitInputType() {
        assertFalse(
            VoiceHomeState(
                modelsReady = true,
                microphoneAllowed = true,
                voiceServiceEnabled = true,
                voiceKeyboardSelected = true
            ).ready
        )
    }
}
