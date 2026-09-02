package com.sanogueralorenzo.voice.models

import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.ViewModelContext
import com.sanogueralorenzo.voice.VoiceApp
import com.sanogueralorenzo.voice.dictation.DictationLanguage

data class LocalModelsState(
    val status: LocalModelsStatus = LocalModelsStatus()
) : MavericksState {
    val loading: Boolean get() = status.loading
    val models: List<LanguageModelStatus> get() = status.models
    val downloadedCount: Int get() = status.downloadedCount
    val operationInProgress: Boolean get() = status.operationInProgress
}

class LocalModelsViewModel(
    initialState: LocalModelsState,
    private val repository: LocalModelsRepository
) : MavericksViewModel<LocalModelsState>(initialState) {

    init {
        repository.status.setOnEach { status -> copy(status = status) }
        repository.refresh()
    }

    fun swapLanguages() {
        repository.swapLanguages()
    }

    fun download(language: DictationLanguage) {
        repository.download(language)
    }

    companion object : MavericksViewModelFactory<LocalModelsViewModel, LocalModelsState> {
        override fun create(
            viewModelContext: ViewModelContext,
            state: LocalModelsState
        ): LocalModelsViewModel {
            val app = viewModelContext.app<VoiceApp>()
            return LocalModelsViewModel(
                initialState = state,
                repository = app.appGraph.localModelsRepository
            )
        }
    }
}
