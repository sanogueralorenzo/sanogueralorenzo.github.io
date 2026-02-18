package com.sanogueralorenzo.voice.theme

import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel

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
}
