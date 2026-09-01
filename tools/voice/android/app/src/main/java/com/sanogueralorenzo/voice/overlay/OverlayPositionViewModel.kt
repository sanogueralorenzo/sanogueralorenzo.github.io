package com.sanogueralorenzo.voice.overlay

import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.ViewModelContext
import com.sanogueralorenzo.voice.VoiceApp

data class OverlayPositionState(
    val bubbleSizeDp: Int = 32,
    val accessibilityServiceEnabled: Boolean = false
) : MavericksState

class OverlayPositionViewModel(
    initialState: OverlayPositionState,
    private val repository: OverlayRepository
) : MavericksViewModel<OverlayPositionState>(initialState) {

    fun refreshStatus() {
        val config = repository.currentConfig()
        setState {
            copy(
                bubbleSizeDp = config.bubbleSizeDp,
                accessibilityServiceEnabled = repository.isAccessibilityServiceEnabled()
            )
        }
    }

    fun setBubbleSizeDp(sizeDp: Int) {
        val clamped = repository.setBubbleSizeDp(sizeDp)
        setState { copy(bubbleSizeDp = clamped) }
    }

    fun adjustBubbleSizeDp(deltaDp: Int) {
        val size = repository.adjustBubbleSizeDp(deltaDp)
        setState { copy(bubbleSizeDp = size) }
    }

    fun nudgeBubblePosition(deltaXDp: Int, deltaYDp: Int) {
        repository.nudgeBubblePositionByDp(deltaXDp, deltaYDp)
    }

    companion object : MavericksViewModelFactory<OverlayPositionViewModel, OverlayPositionState> {
        override fun initialState(viewModelContext: ViewModelContext): OverlayPositionState {
            val repository = OverlayRepository(context = viewModelContext.app<VoiceApp>())
            val config = repository.currentConfig()
            return OverlayPositionState(
                bubbleSizeDp = config.bubbleSizeDp,
                accessibilityServiceEnabled = repository.isAccessibilityServiceEnabled()
            )
        }

        override fun create(
            viewModelContext: ViewModelContext,
            state: OverlayPositionState
        ): OverlayPositionViewModel {
            val repository = OverlayRepository(context = viewModelContext.app<VoiceApp>())
            return OverlayPositionViewModel(
                initialState = state,
                repository = repository
            )
        }
    }
}
