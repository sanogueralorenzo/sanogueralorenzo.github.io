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
            copy(
                llmRewriteEnabled = repository.isLlmRewriteEnabled(),
                capitalizeSentencesEnabled = repository.isCapitalizeSentencesEnabled(),
                removeDotAtEndEnabled = repository.isRemoveDotAtEndEnabled()
            )
        }
    }

    fun setLlmRewriteEnabled(enabled: Boolean) {
        repository.setLlmRewriteEnabled(enabled)
        setState {
            copy(llmRewriteEnabled = enabled)
        }
    }

    fun setCapitalizeSentencesEnabled(enabled: Boolean) {
        repository.setCapitalizeSentencesEnabled(enabled)
        setState {
            copy(capitalizeSentencesEnabled = enabled)
        }
    }

    fun setRemoveDotAtEndEnabled(enabled: Boolean) {
        repository.setRemoveDotAtEndEnabled(enabled)
        setState {
            copy(removeDotAtEndEnabled = enabled)
        }
    }

    companion object : MavericksViewModelFactory<PreferencesViewModel, PreferencesUiState> {
        override fun initialState(viewModelContext: ViewModelContext): PreferencesUiState {
            val repository = viewModelContext.app<VoiceApp>().appGraph.preferencesRepository
            return PreferencesUiState(
                llmRewriteEnabled = repository.isLlmRewriteEnabled(),
                capitalizeSentencesEnabled = repository.isCapitalizeSentencesEnabled(),
                removeDotAtEndEnabled = repository.isRemoveDotAtEndEnabled()
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
