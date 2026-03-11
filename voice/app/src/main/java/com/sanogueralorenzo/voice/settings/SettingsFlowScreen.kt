package com.sanogueralorenzo.voice.settings

import androidx.lifecycle.Lifecycle
import android.content.Context
import android.view.inputmethod.InputMethodManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle as collectFlowAsStateWithLifecycle
import com.airbnb.mvrx.Fail
import com.airbnb.mvrx.Loading
import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.Success
import com.airbnb.mvrx.Uninitialized
import com.airbnb.mvrx.ViewModelContext
import com.airbnb.mvrx.withState
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.voice.VoiceApp
import com.sanogueralorenzo.voice.di.appGraph
import com.sanogueralorenzo.voice.setup.SetupRepository
import com.sanogueralorenzo.voice.prompt.PromptTemplateStore
import com.sanogueralorenzo.voice.ui.OnLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class SettingsFlowState(
    val voiceImeSelected: Boolean = false,
    val homeKeyboardInput: String = "",
    val themeKeyboardInput: String = "",
    val overlayPositionInput: String = "",
    val promptVersion: String? = null,
    val promptDownloading: Boolean = false,
    val promptProgress: Int = 0
) : MavericksState

class SettingsFlowViewModel(
    initialState: SettingsFlowState,
    private val setupRepository: SetupRepository
) : MavericksViewModel<SettingsFlowState>(initialState) {
    init {
        refreshOnResume()
    }

    fun refreshOnResume() {
        refreshKeyboardStatus()
        refreshPromptVersion()
    }

    fun refreshKeyboardStatus() {
        val keyboardStatus = setupRepository.keyboardStatus()
        setState { copy(voiceImeSelected = keyboardStatus.selected) }
    }

    fun refreshPromptVersion() {
        setState { copy(promptVersion = setupRepository.currentPromptVersion()) }
    }

    fun setHomeKeyboardInput(value: String) {
        setState { copy(homeKeyboardInput = value) }
    }

    fun setThemeKeyboardInput(value: String) {
        setState { copy(themeKeyboardInput = value) }
    }

    fun setOverlayPositionInput(value: String) {
        setState { copy(overlayPositionInput = value) }
    }

    fun startPromptDownload() {
        if (withState(this) { it.promptDownloading }) return
        suspend {
            withContext(Dispatchers.IO) { setupRepository.ensurePromptDownloaded(force = false) }
        }.execute { async ->
            when (async) {
                is Loading -> copy(
                    promptDownloading = true,
                    promptProgress = 0
                )

                is Success -> {
                    val result = async()
                    val ready = result is PromptTemplateStore.DownloadResult.Success ||
                        result is PromptTemplateStore.DownloadResult.AlreadyAvailable
                    copy(
                        promptDownloading = false,
                        promptProgress = if (ready) 100 else 0,
                        promptVersion = setupRepository.currentPromptVersion()
                    )
                }

                is Fail -> copy(
                    promptDownloading = false,
                    promptProgress = 0
                )

                is Uninitialized -> this
            }
        }
    }

    fun onImePickerShown() {
        viewModelScope.launch(Dispatchers.IO) {
            repeat(10) {
                delay(250)
                val selected = setupRepository.keyboardStatus().selected
                withContext(Dispatchers.Main) {
                    setState { copy(voiceImeSelected = selected) }
                }
            }
        }
    }

    companion object : MavericksViewModelFactory<SettingsFlowViewModel, SettingsFlowState> {
        override fun create(
            viewModelContext: ViewModelContext,
            state: SettingsFlowState
        ): SettingsFlowViewModel {
            val app = viewModelContext.app<VoiceApp>()
            return SettingsFlowViewModel(
                initialState = state,
                setupRepository = app.appGraph.setupRepository
            )
        }
    }
}

@Composable
fun SettingsFlowScreen() {
    val context = LocalContext.current
    val appContext = remember(context) { context.applicationContext }
    val appGraph = remember(appContext) { appContext.appGraph() }
    val viewModel = mavericksViewModel<SettingsFlowViewModel, SettingsFlowState>()
    val state by viewModel.collectAsStateWithLifecycle()
    val keyboardThemeMode by appGraph.themeRepository.keyboardThemeModeFlow.collectFlowAsStateWithLifecycle()

    OnLifecycle(Lifecycle.Event.ON_RESUME) {
        viewModel.refreshOnResume()
    }

    SettingsNavHost(
        state = state,
        keyboardThemeMode = keyboardThemeMode,
        onHomeInputChange = viewModel::setHomeKeyboardInput,
        onThemeInputChange = viewModel::setThemeKeyboardInput,
        onOverlayPositionInputChange = viewModel::setOverlayPositionInput,
        onDownloadPrompt = viewModel::startPromptDownload,
        onShowImePicker = {
            showImePicker(context)
            viewModel.onImePickerShown()
        }
    )
}

private fun showImePicker(context: Context) {
    val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
    imm.showInputMethodPicker()
}
