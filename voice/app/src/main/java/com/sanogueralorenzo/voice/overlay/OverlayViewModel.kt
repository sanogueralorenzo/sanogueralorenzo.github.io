package com.sanogueralorenzo.voice.overlay

import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.ViewModelContext
import com.sanogueralorenzo.voice.VoiceApp

data class OverlayState(
    val overlayEnabled: Boolean = false,
    val positioningMode: Boolean = false,
    val bubbleX: Int = 0,
    val bubbleY: Int = 0,
    val recordPermissionGranted: Boolean = false,
    val accessibilityServiceEnabled: Boolean = false,
    val voiceImeSelected: Boolean = false
) : MavericksState

class OverlayViewModel(
    initialState: OverlayState,
    private val repository: OverlayRepository
) : MavericksViewModel<OverlayState>(initialState) {

    fun refreshStatus() {
        val config = repository.currentConfig()
        setState {
            copy(
                overlayEnabled = config.overlayEnabled,
                positioningMode = config.positioningMode,
                bubbleX = config.bubbleX,
                bubbleY = config.bubbleY,
                recordPermissionGranted = repository.hasRecordAudioPermission(),
                accessibilityServiceEnabled = repository.isAccessibilityServiceEnabled(),
                voiceImeSelected = repository.isVoiceImeSelected()
            )
        }
    }

    fun setOverlayEnabled(enabled: Boolean) {
        repository.setOverlayEnabled(enabled)
        refreshStatus()
    }

    fun setPositioningMode(enabled: Boolean) {
        repository.setPositioningMode(enabled)
        refreshStatus()
    }

    fun resetBubblePosition() {
        repository.resetBubblePosition()
        refreshStatus()
    }

    companion object : MavericksViewModelFactory<OverlayViewModel, OverlayState> {
        override fun initialState(viewModelContext: ViewModelContext): OverlayState {
            val appGraph = viewModelContext.app<VoiceApp>().appGraph
            val repository = OverlayRepository(
                context = viewModelContext.app<VoiceApp>(),
                setupRepository = appGraph.setupRepository
            )
            val config = repository.currentConfig()
            return OverlayState(
                overlayEnabled = config.overlayEnabled,
                positioningMode = config.positioningMode,
                bubbleX = config.bubbleX,
                bubbleY = config.bubbleY,
                recordPermissionGranted = repository.hasRecordAudioPermission(),
                accessibilityServiceEnabled = repository.isAccessibilityServiceEnabled(),
                voiceImeSelected = repository.isVoiceImeSelected()
            )
        }

        override fun create(
            viewModelContext: ViewModelContext,
            state: OverlayState
        ): OverlayViewModel {
            val appGraph = viewModelContext.app<VoiceApp>().appGraph
            val repository = OverlayRepository(
                context = viewModelContext.app<VoiceApp>(),
                setupRepository = appGraph.setupRepository
            )
            return OverlayViewModel(
                initialState = state,
                repository = repository
            )
        }
    }
}
