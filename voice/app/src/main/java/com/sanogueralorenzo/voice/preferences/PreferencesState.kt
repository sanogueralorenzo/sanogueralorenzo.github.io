package com.sanogueralorenzo.voice.preferences

import com.airbnb.mvrx.MavericksState

data class PreferencesUiState(
    val llmRewriteEnabled: Boolean = true,
    val capitalizeSentencesEnabled: Boolean = false,
    val removeDotAtEndEnabled: Boolean = false
) : MavericksState
