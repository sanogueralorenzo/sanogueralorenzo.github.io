package com.sanogueralorenzo.voice.theme

import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.ViewModelContext
import com.sanogueralorenzo.voice.VoiceApp

data class ThemeState(
    val keyboardThemeMode: KeyboardThemeMode = KeyboardThemeMode.AUTO
) : MavericksState

class ThemeViewModel(
    initialState: ThemeState,
    private val themeRepository: ThemeRepository
) : MavericksViewModel<ThemeState>(initialState) {
    fun refreshKeyboardThemeMode() {
        setState { copy(keyboardThemeMode = themeRepository.keyboardThemeMode()) }
    }

    fun setKeyboardThemeMode(mode: KeyboardThemeMode) {
        themeRepository.setKeyboardThemeMode(mode)
        setState { copy(keyboardThemeMode = mode) }
    }

    companion object : MavericksViewModelFactory<ThemeViewModel, ThemeState> {
        override fun initialState(viewModelContext: ViewModelContext): ThemeState {
            val repository = viewModelContext.app<VoiceApp>().appGraph.themeRepository
            return ThemeState(
                keyboardThemeMode = repository.keyboardThemeMode()
            )
        }

        override fun create(
            viewModelContext: ViewModelContext,
            state: ThemeState
        ): ThemeViewModel {
            val repository = viewModelContext.app<VoiceApp>().appGraph.themeRepository
            return ThemeViewModel(
                initialState = state,
                themeRepository = repository
            )
        }
    }
}
