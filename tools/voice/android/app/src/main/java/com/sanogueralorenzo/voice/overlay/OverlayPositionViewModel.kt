package com.sanogueralorenzo.voice.overlay

import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.ViewModelContext
import com.sanogueralorenzo.voice.VoiceApp

data class OverlayPositionState(
    val bubbleSizeDp: Int = 36,
    val bubbleX: Int = 0,
    val bubbleY: Int = 0,
    val hasCustomBubblePosition: Boolean = false,
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
                bubbleX = config.bubbleX,
                bubbleY = config.bubbleY,
                hasCustomBubblePosition = config.hasCustomBubblePosition,
                accessibilityServiceEnabled = repository.isAccessibilityServiceEnabled()
            )
        }
    }

    fun adjustBubbleSizeDp(deltaDp: Int) {
        val config = repository.adjustBubbleSizeDp(deltaDp)
        setState {
            copy(
                bubbleSizeDp = config.bubbleSizeDp,
                bubbleX = config.bubbleX,
                bubbleY = config.bubbleY,
                hasCustomBubblePosition = config.hasCustomBubblePosition
            )
        }
    }

    fun nudgeBubblePosition(deltaXDp: Int, deltaYDp: Int) {
        repository.nudgeBubblePositionByDp(deltaXDp, deltaYDp)
        val config = repository.currentConfig()
        setState {
            copy(
                bubbleX = config.bubbleX,
                bubbleY = config.bubbleY,
                hasCustomBubblePosition = config.hasCustomBubblePosition
            )
        }
    }

    fun setBubblePosition(x: Int, y: Int) {
        repository.setBubblePosition(x, y)
        setState {
            copy(
                bubbleX = x.coerceAtLeast(0),
                bubbleY = y.coerceAtLeast(0),
                hasCustomBubblePosition = true
            )
        }
    }

    fun setDefaultBubblePosition(x: Int, y: Int) {
        repository.setDefaultBubblePosition(x, y)
        setState {
            copy(
                bubbleX = x.coerceAtLeast(0),
                bubbleY = y.coerceAtLeast(0),
                hasCustomBubblePosition = false
            )
        }
    }

    companion object : MavericksViewModelFactory<OverlayPositionViewModel, OverlayPositionState> {
        override fun initialState(viewModelContext: ViewModelContext): OverlayPositionState {
            val repository = OverlayRepository(context = viewModelContext.app<VoiceApp>())
            val config = repository.currentConfig()
            return OverlayPositionState(
                bubbleSizeDp = config.bubbleSizeDp,
                bubbleX = config.bubbleX,
                bubbleY = config.bubbleY,
                hasCustomBubblePosition = config.hasCustomBubblePosition,
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
