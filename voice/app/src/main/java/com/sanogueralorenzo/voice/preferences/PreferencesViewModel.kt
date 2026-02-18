package com.sanogueralorenzo.voice.preferences

import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.ViewModelContext
import com.sanogueralorenzo.voice.VoiceApp

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

    companion object : MavericksViewModelFactory<PreferencesViewModel, PreferencesUiState> {
        override fun initialState(viewModelContext: ViewModelContext): PreferencesUiState {
            val repository = viewModelContext.app<VoiceApp>().appGraph.preferencesRepository
            return PreferencesUiState(
                rewriteEnabled = repository.isLiteRtRewriteEnabled()
            )
        }

        override fun create(
            viewModelContext: ViewModelContext,
            state: PreferencesUiState
        ): PreferencesViewModel {
            val repository = viewModelContext.app<VoiceApp>().appGraph.preferencesRepository
            return PreferencesViewModel(
                initialState = state,
                repository = repository
            )
        }
    }
}
