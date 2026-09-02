package com.sanogueralorenzo.voice.product

import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.ViewModelContext
import com.sanogueralorenzo.voice.VoiceApp
import com.sanogueralorenzo.voice.setup.VoiceSetupRepository
import com.sanogueralorenzo.voice.setup.VoiceSetupStatus

data class VoiceHomeState(
    val setup: VoiceSetupStatus = VoiceSetupStatus()
) : MavericksState {
    val loading: Boolean get() = setup.loading
    val modelsReady: Boolean get() = setup.modelsReady
    val microphoneAllowed: Boolean get() = setup.microphoneAllowed
    val voiceServiceEnabled: Boolean get() = setup.overlayServiceEnabled
    val voiceKeyboardEnabled: Boolean get() = setup.keyboardEnabled
    val voiceKeyboardSelected: Boolean get() = setup.keyboardSelected
    val inputType: VoiceInputType? get() = setup.inputType
    val ready: Boolean get() = setup.ready
}

class VoiceHomeViewModel(
    initialState: VoiceHomeState,
    private val setupRepository: VoiceSetupRepository
) : MavericksViewModel<VoiceHomeState>(initialState) {

    init {
        setupRepository.status.setOnEach { status -> copy(setup = status) }
        setupRepository.refresh()
    }

    fun refreshStatus() {
        setupRepository.refresh()
    }

    fun selectInputType(inputType: VoiceInputType) {
        setupRepository.selectInputType(inputType)
    }

    companion object : MavericksViewModelFactory<VoiceHomeViewModel, VoiceHomeState> {
        override fun create(
            viewModelContext: ViewModelContext,
            state: VoiceHomeState
        ): VoiceHomeViewModel {
            val app = viewModelContext.app<VoiceApp>()
            return VoiceHomeViewModel(
                initialState = state,
                setupRepository = app.appGraph.voiceSetupRepository
            )
        }
    }
}
