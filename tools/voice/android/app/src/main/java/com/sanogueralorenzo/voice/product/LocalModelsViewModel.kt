package com.sanogueralorenzo.voice.product

import androidx.lifecycle.viewModelScope
import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.ViewModelContext
import com.airbnb.mvrx.withState
import com.sanogueralorenzo.voice.VoiceApp
import com.sanogueralorenzo.voice.audio.DictationLanguage
import com.sanogueralorenzo.voice.audio.DictationLanguagePreferences
import com.sanogueralorenzo.voice.audio.DictationLanguages
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class LanguageModelState(
    val language: DictationLanguage,
    val orderIndex: Int? = null,
    val ready: Boolean = false,
    val downloading: Boolean = false,
    val progress: Int = 0,
    val error: String? = null
)

data class LocalModelsState(
    val loading: Boolean = true,
    val models: List<LanguageModelState> = DictationLanguage.entries.map(::LanguageModelState)
) : MavericksState {
    val downloadedCount: Int
        get() = models.count { it.ready }

    val operationInProgress: Boolean
        get() = models.any { it.downloading }
}

class LocalModelsViewModel(
    initialState: LocalModelsState,
    private val languagePreferences: DictationLanguagePreferences,
    private val localModelsDownloader: LocalModelsDownloader
) : MavericksViewModel<LocalModelsState>(initialState) {

    init {
        refresh()
    }

    private fun refresh() {
        viewModelScope.launch {
            val readiness = withContext(Dispatchers.IO) {
                DictationLanguage.entries.associateWith(localModelsDownloader::isReady)
            }
            val ordered = languagePreferences.syncDownloaded(
                readiness.filterValues { it }.keys
            )
            setState {
                copy(
                    loading = false,
                    models = buildModelStates(ordered, readiness)
                )
            }
        }
    }

    fun moveBefore(language: DictationLanguage, target: DictationLanguage) {
        val canMove = withState(this) { state ->
            !state.loading && !state.operationInProgress && state.downloadedCount > 1 &&
                state.models.any { it.language == language && it.ready } &&
                state.models.any { it.language == target && it.ready }
        }
        if (!canMove) return
        updateOrdering(languagePreferences.moveBefore(language, target))
    }

    fun download(language: DictationLanguage) {
        val canStart = withState(this) { state ->
            !state.loading && !state.operationInProgress &&
                state.models.any { it.language == language && !it.ready }
        }
        if (!canStart) return

        setState {
            copy(
                models = models.map { model ->
                    if (model.language == language) {
                        model.copy(downloading = true, progress = 0, error = null)
                    } else {
                        model
                    }
                }
            )
        }
        viewModelScope.launch {
            when (val result = localModelsDownloader.download(language) { progress ->
                setState {
                    copy(
                        models = models.map { model ->
                            if (model.language == language) model.copy(progress = progress)
                            else model
                        }
                    )
                }
            }) {
                LocalModelsDownloadResult.Success -> {
                    val downloaded = withState(this@LocalModelsViewModel) { state ->
                        state.models
                            .filter { it.ready }
                            .mapTo(mutableSetOf()) { it.language }
                    } + language
                    val ordered = languagePreferences.syncDownloaded(downloaded)
                    setState {
                        copy(
                            models = models.map { model ->
                                if (model.language == language) {
                                    model.copy(
                                        ready = true,
                                        downloading = false,
                                        progress = 100,
                                        error = null
                                    )
                                } else {
                                    model
                                }
                            }
                                .withOrdering(ordered)
                        )
                    }
                }

                is LocalModelsDownloadResult.Failure -> setState {
                    copy(
                        models = models.map { model ->
                            if (model.language == language) {
                                model.copy(downloading = false, error = result.message)
                            } else {
                                model
                            }
                        }
                    )
                }
            }
        }
    }

    private fun updateOrdering(languages: DictationLanguages) {
        setState {
            copy(
                models = models.withOrdering(languages.ordered)
            )
        }
    }

    private fun buildModelStates(
        ordered: List<DictationLanguage>,
        readiness: Map<DictationLanguage, Boolean>
    ): List<LanguageModelState> {
        return DictationLanguage.entries.map { language ->
            LanguageModelState(
                language = language,
                orderIndex = ordered.indexOf(language).takeIf { it >= 0 },
                ready = readiness[language] == true
            )
        }.sortedWith(modelOrderComparator)
    }

    private fun List<LanguageModelState>.withOrdering(
        ordered: List<DictationLanguage>
    ): List<LanguageModelState> {
        return map { model ->
            model.copy(orderIndex = ordered.indexOf(model.language).takeIf { it >= 0 })
        }.sortedWith(modelOrderComparator)
    }

    companion object : MavericksViewModelFactory<LocalModelsViewModel, LocalModelsState> {
        private val modelOrderComparator = compareBy<LanguageModelState>(
            { it.orderIndex == null },
            { it.orderIndex ?: Int.MAX_VALUE },
            { it.language.ordinal }
        )

        override fun create(
            viewModelContext: ViewModelContext,
            state: LocalModelsState
        ): LocalModelsViewModel {
            val app = viewModelContext.app<VoiceApp>()
            return LocalModelsViewModel(
                initialState = state,
                languagePreferences = app.appGraph.languagePreferences,
                localModelsDownloader = LocalModelsDownloader(app)
            )
        }
    }
}
