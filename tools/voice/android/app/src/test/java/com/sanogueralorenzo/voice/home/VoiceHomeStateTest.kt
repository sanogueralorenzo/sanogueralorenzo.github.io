package com.sanogueralorenzo.voice.home

import com.sanogueralorenzo.voice.setup.VoiceInputType
import com.sanogueralorenzo.voice.setup.VoiceSetupStatus
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class VoiceHomeStateTest {
    @Test
    fun keyboardReadyRequiresSelectedVoiceKeyboard() {
        assertTrue(
            VoiceHomeState(
                setup = VoiceSetupStatus(
                    modelsReady = true,
                    microphoneAllowed = true,
                    keyboardSelected = true,
                    inputType = VoiceInputType.KEYBOARD
                )
            ).ready
        )
        assertFalse(
            VoiceHomeState(
                setup = VoiceSetupStatus(
                    modelsReady = true,
                    microphoneAllowed = true,
                    overlayServiceEnabled = true,
                    inputType = VoiceInputType.KEYBOARD
                )
            ).ready
        )
    }

    @Test
    fun overlayReadyRequiresVoiceService() {
        assertTrue(
            VoiceHomeState(
                setup = VoiceSetupStatus(
                    modelsReady = true,
                    microphoneAllowed = true,
                    overlayServiceEnabled = true,
                    inputType = VoiceInputType.OVERLAY
                )
            ).ready
        )
        assertFalse(
            VoiceHomeState(
                setup = VoiceSetupStatus(
                    modelsReady = true,
                    microphoneAllowed = true,
                    keyboardSelected = true,
                    inputType = VoiceInputType.OVERLAY
                )
            ).ready
        )
    }

    @Test
    fun readyRequiresAnExplicitInputType() {
        assertFalse(
            VoiceHomeState(
                setup = VoiceSetupStatus(
                    modelsReady = true,
                    microphoneAllowed = true,
                    overlayServiceEnabled = true,
                    keyboardSelected = true
                )
            ).ready
        )
    }
}
