package com.sanogueralorenzo.voice.preferences

import com.airbnb.mvrx.MavericksViewModel

class PreferencesViewModel(
    initialState: PreferencesUiState,
    private val repository: PreferencesRepository
) : MavericksViewModel<PreferencesUiState>(initialState) {

    fun refreshPreferences() {
        setState {
            copy(rewriteEnabled = repository.isLiteRtRewriteEnabled())
        }
    }

    fun setRewriteEnabled(enabled: Boolean) {
        repository.setLiteRtRewriteEnabled(enabled)
        setState {
            copy(rewriteEnabled = enabled)
        }
    }
}
