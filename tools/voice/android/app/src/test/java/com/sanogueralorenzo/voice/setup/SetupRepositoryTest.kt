package com.sanogueralorenzo.voice.setup

import org.junit.Assert.assertEquals
import org.junit.Test

class SetupRepositoryTest {
    @Test
    fun requiredStep_returnsModels_whenAllCoreItemsMissing() {
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
                setupComplete = false
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
                setupComplete = false
            )
        )
    }

    @Test
    fun requiredStep_returnsMic_whenOnlyMicMissing() {
        val missing = SetupRepository.MissingSetupItems(
            micPermission = true,
            imeEnabled = false,
            liteRtModel = false,
            moonshineModel = false,
            promptTemplate = false
        )

        assertEquals(
            SetupRepository.RequiredStep.MIC_PERMISSION,
            SetupRepository.requiredStepForMissing(
                missing = missing,
                setupComplete = false
            )
        )
    }

    @Test
    fun requiredStep_returnsSelectKeyboard_whenRequirementsReadyButSetupIncomplete() {
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
                setupComplete = false
            )
        )
    }

    @Test
    fun requiredStep_returnsComplete_whenRequirementsReadyAndSetupComplete() {
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
                setupComplete = true
            )
        )
    }
}
