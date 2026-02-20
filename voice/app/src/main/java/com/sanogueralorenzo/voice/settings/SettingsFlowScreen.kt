package com.sanogueralorenzo.voice.settings

import android.content.Context
import android.view.inputmethod.InputMethodManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle as collectFlowAsStateWithLifecycle
import com.airbnb.mvrx.Async
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
import com.sanogueralorenzo.voice.setup.ModelReadiness
import com.sanogueralorenzo.voice.setup.SetupRepository
import com.sanogueralorenzo.voice.prompt.PromptTemplateStore
import com.sanogueralorenzo.voice.ui.OnResume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class SettingsFlowState(
    val voiceImeSelected: Boolean = false,
    val homeKeyboardInput: String = "",
    val themeKeyboardInput: String = "",
    val liteRtReady: Boolean = false,
    val moonshineReady: Boolean = false,
    val promptReady: Boolean = false,
    val promptVersion: String? = null,
    val promptDownloading: Boolean = false,
    val promptProgress: Int = 0,
    val modelReadinessAsync: Async<ModelReadiness> = Uninitialized,
    val promptDownloadAsync: Async<PromptTemplateStore.DownloadResult> = Uninitialized
) : MavericksState

class SettingsFlowViewModel(
    initialState: SettingsFlowState,
    private val setupRepository: SetupRepository
) : MavericksViewModel<SettingsFlowState>(initialState) {
    fun refreshKeyboardStatus() {
        val keyboardStatus = setupRepository.keyboardStatus()
        setState { copy(voiceImeSelected = keyboardStatus.selected) }
    }

    fun refreshModelReadiness() {
        suspend {
            withContext(Dispatchers.IO) { setupRepository.readModelReadiness() }
        }.execute { async ->
            when (async) {
                is Success -> copy(
                    modelReadinessAsync = async,
                    liteRtReady = async().liteRtReady,
                    moonshineReady = async().moonshineReady,
                    promptReady = async().promptReady,
                    promptVersion = async().promptVersion
                )

                else -> copy(modelReadinessAsync = async)
            }
        }
    }

    fun setHomeKeyboardInput(value: String) {
        setState { copy(homeKeyboardInput = value) }
    }

    fun setThemeKeyboardInput(value: String) {
        setState { copy(themeKeyboardInput = value) }
    }

    fun startPromptDownload() {
        if (withState(this) { it.promptDownloading }) return
        suspend {
            withContext(Dispatchers.IO) { setupRepository.ensurePromptDownloaded(force = false) }
        }.execute { async ->
            when (async) {
                is Loading -> copy(
                    promptDownloadAsync = async,
                    promptDownloading = true,
                    promptProgress = 0
                )

                is Success -> {
                    val result = async()
                    val ready = result is PromptTemplateStore.DownloadResult.Success ||
                        result is PromptTemplateStore.DownloadResult.AlreadyAvailable
                    copy(
                        promptDownloadAsync = async,
                        promptDownloading = false,
                        promptReady = ready,
                        promptProgress = if (ready) 100 else 0,
                        promptVersion = setupRepository.currentPromptVersion()
                    )
                }

                is Fail -> copy(
                    promptDownloadAsync = async,
                    promptDownloading = false,
                    promptProgress = 0
                )

                is Uninitialized -> copy(promptDownloadAsync = async)
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
    val scope = rememberCoroutineScope()

    OnResume {
        viewModel.refreshKeyboardStatus()
        viewModel.refreshModelReadiness()
    }

    LaunchedEffect(Unit) {
        viewModel.refreshKeyboardStatus()
        viewModel.refreshModelReadiness()
    }

    SettingsNavHost(
        state = state,
        keyboardThemeMode = keyboardThemeMode,
        onHomeInputChange = viewModel::setHomeKeyboardInput,
        onThemeInputChange = viewModel::setThemeKeyboardInput,
        onDownloadPrompt = viewModel::startPromptDownload,
        onShowImePicker = {
            showImePicker(context)
            scope.launch {
                repeat(10) {
                    delay(250)
                    viewModel.refreshKeyboardStatus()
                }
            }
        }
    )
}

private fun showImePicker(context: Context) {
    val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
    imm.showInputMethodPicker()
}
