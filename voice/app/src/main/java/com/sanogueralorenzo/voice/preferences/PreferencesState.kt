package com.sanogueralorenzo.voice.preferences

import com.airbnb.mvrx.MavericksState

data class PreferencesUiState(
    val rewriteEnabled: Boolean = true
) : MavericksState
