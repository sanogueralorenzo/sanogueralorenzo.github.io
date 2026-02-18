package com.sanogueralorenzo.voice.theme

import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.ViewModelContext
import com.sanogueralorenzo.voice.VoiceApp

data class ThemeUiState(
    val keyboardThemeMode: KeyboardThemeMode = KeyboardThemeMode.AUTO
) : MavericksState

class ThemeViewModel(
    initialState: ThemeUiState,
    private val themeRepository: ThemeRepository
) : MavericksViewModel<ThemeUiState>(initialState) {
    fun refreshKeyboardThemeMode() {
        setState { copy(keyboardThemeMode = themeRepository.keyboardThemeMode()) }
    }

    fun setKeyboardThemeMode(mode: KeyboardThemeMode) {
        themeRepository.setKeyboardThemeMode(mode)
        setState { copy(keyboardThemeMode = mode) }
    }

    companion object : MavericksViewModelFactory<ThemeViewModel, ThemeUiState> {
        override fun initialState(viewModelContext: ViewModelContext): ThemeUiState {
            val repository = viewModelContext.app<VoiceApp>().appGraph.themeRepository
            return ThemeUiState(
                keyboardThemeMode = repository.keyboardThemeMode()
            )
        }

        override fun create(
            viewModelContext: ViewModelContext,
            state: ThemeUiState
        ): ThemeViewModel {
            val repository = viewModelContext.app<VoiceApp>().appGraph.themeRepository
            return ThemeViewModel(
                initialState = state,
                themeRepository = repository
            )
        }
    }
}
