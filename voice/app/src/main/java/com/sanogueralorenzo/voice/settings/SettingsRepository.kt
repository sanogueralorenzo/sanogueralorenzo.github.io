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
        return setupRepository.requiredStep(
            introDismissed = false
        ) != SetupRepository.RequiredStep.COMPLETE
    }
}
