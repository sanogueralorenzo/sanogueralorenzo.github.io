package com.sanogueralorenzo.voice.overlay

import com.airbnb.mvrx.Async
import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.Success
import com.airbnb.mvrx.Uninitialized
import com.airbnb.mvrx.ViewModelContext
import com.sanogueralorenzo.voice.VoiceApp
import kotlinx.coroutines.Dispatchers

data class OverlayPositionState(
    val positionConfig: Async<OverlayConfig> = Uninitialized,
    val bubbleSizeDp: Int = 36,
    val bubbleX: Int = 0,
    val bubbleY: Int = 0,
    val hasCustomBubblePosition: Boolean = false,
    val accessibilityServiceEnabled: Boolean = false
) : MavericksState {
    val positionLoaded: Boolean
        get() = positionConfig is Success
}

class OverlayPositionViewModel(
    initialState: OverlayPositionState,
    private val repository: OverlayRepository
) : MavericksViewModel<OverlayPositionState>(initialState) {

    init {
        loadPositionConfig()
        refreshStatus()
    }

    private fun loadPositionConfig() {
        suspend { repository.readConfig() }.execute(Dispatchers.IO) { asyncConfig ->
            val config = asyncConfig()
            copy(
                positionConfig = asyncConfig,
                bubbleSizeDp = config?.bubbleSizeDp ?: bubbleSizeDp,
                bubbleX = config?.bubbleX ?: bubbleX,
                bubbleY = config?.bubbleY ?: bubbleY,
                hasCustomBubblePosition =
                    config?.hasCustomBubblePosition ?: hasCustomBubblePosition
            )
        }
    }

    fun refreshStatus() {
        setState {
            copy(
                accessibilityServiceEnabled = repository.isAccessibilityServiceEnabled()
            )
        }
    }

    fun adjustBubbleSizeDp(deltaDp: Int) {
        val config = repository.adjustBubbleSizeDp(deltaDp)
        setState {
            copy(
                positionConfig = Success(config),
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
                positionConfig = Success(config),
                bubbleX = config.bubbleX,
                bubbleY = config.bubbleY,
                hasCustomBubblePosition = config.hasCustomBubblePosition
            )
        }
    }

    fun setBubblePosition(x: Int, y: Int) {
        repository.setBubblePosition(x, y)
        val config = repository.currentConfig()
        setState {
            copy(
                positionConfig = Success(config),
                bubbleX = config.bubbleX,
                bubbleY = config.bubbleY,
                hasCustomBubblePosition = config.hasCustomBubblePosition
            )
        }
    }

    fun setDefaultBubblePosition(x: Int, y: Int) {
        repository.setDefaultBubblePosition(x, y)
        val config = repository.currentConfig()
        setState {
            copy(
                positionConfig = Success(config),
                bubbleX = config.bubbleX,
                bubbleY = config.bubbleY,
                hasCustomBubblePosition = config.hasCustomBubblePosition
            )
        }
    }

    companion object : MavericksViewModelFactory<OverlayPositionViewModel, OverlayPositionState> {
        override fun initialState(viewModelContext: ViewModelContext): OverlayPositionState {
            return OverlayPositionState()
        }

        override fun create(
            viewModelContext: ViewModelContext,
            state: OverlayPositionState
        ): OverlayPositionViewModel {
            val repository = viewModelContext.app<VoiceApp>().appGraph.overlayRepository
            return OverlayPositionViewModel(
                initialState = state,
                repository = repository
            )
        }
    }
}
