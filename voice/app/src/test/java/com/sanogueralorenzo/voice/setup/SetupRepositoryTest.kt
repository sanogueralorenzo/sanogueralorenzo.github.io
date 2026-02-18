package com.sanogueralorenzo.voice.setup

import org.junit.Assert.assertEquals
import org.junit.Test

class SetupRepositoryTest {
    @Test
    fun requiredStep_returnsIntro_whenAllCoreItemsMissingAndNotDismissed() {
        val snapshot = SetupRepository.SetupSnapshot(
            micGranted = false,
            voiceImeEnabled = false,
            keyboardSelected = false,
            liteRtReady = false,
            moonshineReady = false,
            promptReady = false,
            introDismissed = false
        )

        assertEquals(SetupRepository.RequiredStep.INTRO, SetupRepository.requiredStep(snapshot))
    }

    @Test
    fun requiredStep_skipsIntroAfterDismiss_andContinuesWithMicStep() {
        val snapshot = SetupRepository.SetupSnapshot(
            micGranted = false,
            voiceImeEnabled = false,
            keyboardSelected = false,
            liteRtReady = false,
            moonshineReady = false,
            promptReady = false,
            introDismissed = true
        )

        assertEquals(SetupRepository.RequiredStep.MIC_PERMISSION, SetupRepository.requiredStep(snapshot))
    }

    @Test
    fun requiredStep_returnsComplete_whenEverythingReady() {
        val snapshot = SetupRepository.SetupSnapshot(
            micGranted = true,
            voiceImeEnabled = true,
            keyboardSelected = true,
            liteRtReady = true,
            moonshineReady = true,
            promptReady = true,
            introDismissed = true
        )

        assertEquals(SetupRepository.RequiredStep.COMPLETE, SetupRepository.requiredStep(snapshot))
    }
}
