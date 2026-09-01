package com.sanogueralorenzo.voice.product

import androidx.lifecycle.viewModelScope
import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.ViewModelContext
import com.sanogueralorenzo.voice.VoiceApp
import com.sanogueralorenzo.voice.audio.DictationLanguage
import com.sanogueralorenzo.voice.audio.DictationLanguagePreferences
import com.sanogueralorenzo.voice.keyboard.VoiceKeyboardStatus
import com.sanogueralorenzo.voice.keyboard.VoiceKeyboardStatusReader
import com.sanogueralorenzo.voice.overlay.OverlayRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class VoiceHomeState(
    val loading: Boolean = true,
    val modelsReady: Boolean = false,
    val activeLanguages: List<DictationLanguage> = emptyList(),
    val microphoneAllowed: Boolean = false,
    val voiceServiceEnabled: Boolean = false,
    val voiceKeyboardEnabled: Boolean = false,
    val voiceKeyboardSelected: Boolean = false
) : MavericksState {
    val ready: Boolean
        get() = modelsReady && microphoneAllowed && voiceServiceEnabled
}

class VoiceHomeViewModel(
    initialState: VoiceHomeState,
    private val overlayRepository: OverlayRepository,
    private val readDownloadedLanguages: () -> Set<DictationLanguage>,
    private val readKeyboardStatus: () -> VoiceKeyboardStatus,
    private val languagePreferences: DictationLanguagePreferences
) : MavericksViewModel<VoiceHomeState>(initialState) {

    init {
        refreshStatus()
    }

    fun refreshStatus() {
        viewModelScope.launch {
            val downloadedLanguages = withContext(Dispatchers.IO) { readDownloadedLanguages() }
            val activeLanguages = languagePreferences.syncDownloaded(downloadedLanguages)
            val microphoneAllowed = overlayRepository.hasRecordAudioPermission()
            val voiceServiceEnabled = overlayRepository.isAccessibilityServiceEnabled()
            val keyboardStatus = readKeyboardStatus()
            if (voiceServiceEnabled && !overlayRepository.currentConfig().overlayEnabled) {
                overlayRepository.setOverlayEnabled(true)
            }

            setState {
                copy(
                    loading = false,
                    modelsReady = activeLanguages.isNotEmpty(),
                    activeLanguages = activeLanguages,
                    microphoneAllowed = microphoneAllowed,
                    voiceServiceEnabled = voiceServiceEnabled,
                    voiceKeyboardEnabled = keyboardStatus.enabled,
                    voiceKeyboardSelected = keyboardStatus.selected
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
                readDownloadedLanguages = {
                    app.appGraph.modelSetupRepository.readDownloadedLanguages()
                },
                readKeyboardStatus = {
                    VoiceKeyboardStatusReader.read(app)
                },
                languagePreferences = app.appGraph.languagePreferences
            )
        }
    }
}
