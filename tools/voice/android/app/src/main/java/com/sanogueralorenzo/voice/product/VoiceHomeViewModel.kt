package com.sanogueralorenzo.voice.product

import androidx.lifecycle.viewModelScope
import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.ViewModelContext
import com.sanogueralorenzo.voice.VoiceApp
import com.sanogueralorenzo.voice.overlay.OverlayRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class VoiceHomeState(
    val loading: Boolean = true,
    val modelsReady: Boolean = false,
    val microphoneAllowed: Boolean = false,
    val voiceServiceEnabled: Boolean = false
) : MavericksState {
    val ready: Boolean
        get() = modelsReady && microphoneAllowed && voiceServiceEnabled
}

class VoiceHomeViewModel(
    initialState: VoiceHomeState,
    private val overlayRepository: OverlayRepository,
    private val readModelsReady: () -> Boolean
) : MavericksViewModel<VoiceHomeState>(initialState) {

    init {
        refreshStatus()
    }

    fun refreshStatus() {
        viewModelScope.launch {
            val modelsReady = withContext(Dispatchers.IO) { readModelsReady() }
            val microphoneAllowed = overlayRepository.hasRecordAudioPermission()
            val voiceServiceEnabled = overlayRepository.isAccessibilityServiceEnabled()

            if (voiceServiceEnabled && !overlayRepository.currentConfig().overlayEnabled) {
                overlayRepository.setOverlayEnabled(true)
            }

            setState {
                copy(
                    loading = false,
                    modelsReady = modelsReady,
                    microphoneAllowed = microphoneAllowed,
                    voiceServiceEnabled = voiceServiceEnabled
                )
            }
        }
    }

    companion object : MavericksViewModelFactory<VoiceHomeViewModel, VoiceHomeState> {
        override fun create(
            viewModelContext: ViewModelContext,
            state: VoiceHomeState
        ): VoiceHomeViewModel {
            val app = viewModelContext.app<VoiceApp>()
            val overlayRepository = OverlayRepository(context = app)
            return VoiceHomeViewModel(
                initialState = state,
                overlayRepository = overlayRepository,
                readModelsReady = {
                    app.appGraph.modelSetupRepository.readModelReadiness().allReady
                }
            )
        }
    }
}
