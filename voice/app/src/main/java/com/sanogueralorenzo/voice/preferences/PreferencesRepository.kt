package com.sanogueralorenzo.voice.preferences

import com.sanogueralorenzo.voice.settings.VoiceSettingsStore
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn

@Inject
@SingleIn(AppScope::class)
class PreferencesRepository(
    private val settingsStore: VoiceSettingsStore
) {
    fun isLiteRtRewriteEnabled(): Boolean {
        return settingsStore.isLiteRtRewriteEnabled()
    }

    fun setLiteRtRewriteEnabled(enabled: Boolean) {
        settingsStore.setLiteRtRewriteEnabled(enabled)
    }
}
