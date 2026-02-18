package com.sanogueralorenzo.voice.setup

import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.sanogueralorenzo.voice.settings.KeyboardThemeMode
import com.sanogueralorenzo.voice.settings.ThemeRepository

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
