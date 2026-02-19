package com.sanogueralorenzo.voice.setup

import org.junit.Assert.assertEquals
import org.junit.Test

class SetupRepositoryTest {
    @Test
    fun requiredStep_returnsIntro_whenAllCoreItemsMissingAndNotDismissed() {
        val missing = SetupRepository.MissingSetupItems(
            micPermission = true,
            imeEnabled = true,
            liteRtModel = true,
            moonshineModel = true,
            promptTemplate = true
        )

        assertEquals(
            SetupRepository.RequiredStep.INTRO,
            SetupRepository.requiredStepForMissing(
                missing = missing,
                introDismissed = false,
                setupSelectKeyboardDone = false
            )
        )
    }

    @Test
    fun requiredStep_skipsIntroAfterDismiss_andContinuesWithModelsStep() {
        val missing = SetupRepository.MissingSetupItems(
            micPermission = true,
            imeEnabled = true,
            liteRtModel = true,
            moonshineModel = true,
            promptTemplate = true
        )

        assertEquals(
            SetupRepository.RequiredStep.DOWNLOAD_MODELS,
            SetupRepository.requiredStepForMissing(
                missing = missing,
                introDismissed = true,
                setupSelectKeyboardDone = false
            )
        )
    }

    @Test
    fun requiredStep_prioritizesModelsBeforeMicAndKeyboard() {
        val missing = SetupRepository.MissingSetupItems(
            micPermission = true,
            imeEnabled = true,
            liteRtModel = true,
            moonshineModel = false,
            promptTemplate = false
        )

        assertEquals(
            SetupRepository.RequiredStep.DOWNLOAD_MODELS,
            SetupRepository.requiredStepForMissing(
                missing = missing,
                introDismissed = true,
                setupSelectKeyboardDone = false
            )
        )
    }

    @Test
    fun requiredStep_returnsSelectKeyboard_whenEverythingReadyButFinalStepNotDone() {
        val missing = SetupRepository.MissingSetupItems(
            micPermission = false,
            imeEnabled = false,
            liteRtModel = false,
            moonshineModel = false,
            promptTemplate = false
        )

        assertEquals(
            SetupRepository.RequiredStep.SELECT_KEYBOARD,
            SetupRepository.requiredStepForMissing(
                missing = missing,
                introDismissed = true,
                setupSelectKeyboardDone = false
            )
        )
    }

    @Test
    fun requiredStep_returnsComplete_whenEverythingReady() {
        val missing = SetupRepository.MissingSetupItems(
            micPermission = false,
            imeEnabled = false,
            liteRtModel = false,
            moonshineModel = false,
            promptTemplate = false
        )

        assertEquals(
            SetupRepository.RequiredStep.COMPLETE,
            SetupRepository.requiredStepForMissing(
                missing = missing,
                introDismissed = true,
                setupSelectKeyboardDone = true
            )
        )
    }
}
