package com.sanogueralorenzo.voice.settings

import com.sanogueralorenzo.voice.setup.SetupRepository
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn

@Inject
@SingleIn(AppScope::class)
class SettingsRepository(
    private val setupRepository: SetupRepository
) {
    fun shouldStartInSetup(): Boolean {
        val requiredStep = setupRepository.requiredStep(
            introDismissed = false
        )
        if (requiredStep != SetupRepository.RequiredStep.COMPLETE) return true
        return !setupRepository.isSetupSelectKeyboardStepDone()
    }
}
