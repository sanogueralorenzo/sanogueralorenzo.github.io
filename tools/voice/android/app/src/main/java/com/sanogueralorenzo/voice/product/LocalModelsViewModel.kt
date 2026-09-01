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
    val enabled: Boolean = false,
    val orderIndex: Int? = null,
    val ready: Boolean = false,
    val downloading: Boolean = false,
    val progress: Int = 0,
    val removing: Boolean = false,
    val error: String? = null
)

data class LocalModelsState(
    val loading: Boolean = true,
    val models: List<LanguageModelState> = DictationLanguage.entries.map(::LanguageModelState)
) : MavericksState {
    val enabledCount: Int
        get() = models.count { it.enabled }

    val operationInProgress: Boolean
        get() = models.any { it.downloading || it.removing }
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
            val languages = languagePreferences.read()
            val readiness = withContext(Dispatchers.IO) {
                DictationLanguage.entries.associateWith(localModelsDownloader::isReady)
            }
            setState {
                copy(
                    loading = false,
                    models = buildModelStates(languages, readiness)
                )
            }
        }
    }

    fun setEnabled(language: DictationLanguage, enabled: Boolean) {
        if (withState(this) { it.operationInProgress }) return
        val languages = languagePreferences.setEnabled(language, enabled)
        updateOrdering(languages)
    }

    fun moveEarlier(language: DictationLanguage) {
        if (withState(this) { it.operationInProgress }) return
        updateOrdering(languagePreferences.moveEarlier(language))
    }

    fun moveLater(language: DictationLanguage) {
        if (withState(this) { it.operationInProgress }) return
        updateOrdering(languagePreferences.moveLater(language))
    }

    fun download(language: DictationLanguage) {
        val canStart = withState(this) { state ->
            !state.loading && !state.operationInProgress &&
                state.models.any { it.language == language && it.enabled && !it.ready }
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
                LocalModelsDownloadResult.Success -> setState {
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
                    )
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

    fun remove(language: DictationLanguage) {
        val canStart = withState(this) { state ->
            !state.loading && !state.operationInProgress &&
                state.models.any { it.language == language && it.ready }
        }
        if (!canStart) return

        setState {
            copy(
                models = models.map { model ->
                    if (model.language == language) model.copy(removing = true, error = null)
                    else model
                }
            )
        }
        viewModelScope.launch {
            withContext(Dispatchers.IO) { localModelsDownloader.remove(language) }
            setState {
                copy(
                    models = models.map { model ->
                        if (model.language == language) {
                            model.copy(ready = false, removing = false, progress = 0)
                        } else {
                            model
                        }
                    }
                )
            }
        }
    }

    private fun updateOrdering(languages: DictationLanguages) {
        setState {
            copy(
                models = models.map { model ->
                    model.copy(
                        enabled = languages.isEnabled(model.language),
                        orderIndex = languages.ordered.indexOf(model.language).takeIf { it >= 0 }
                    )
                }.sortedWith(modelOrderComparator)
            )
        }
    }

    private fun buildModelStates(
        languages: DictationLanguages,
        readiness: Map<DictationLanguage, Boolean>
    ): List<LanguageModelState> {
        return DictationLanguage.entries.map { language ->
            LanguageModelState(
                language = language,
                enabled = languages.isEnabled(language),
                orderIndex = languages.ordered.indexOf(language).takeIf { it >= 0 },
                ready = readiness[language] == true
            )
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
