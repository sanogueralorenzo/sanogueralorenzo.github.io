package com.sanogueralorenzo.voice.setup

import android.Manifest
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewModelScope
import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.ViewModelContext
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.voice.VoiceApp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

enum class SetupDestination {
    SPLASH,
    INTRO,
    DOWNLOAD_MODELS,
    MIC_PERMISSION,
    ENABLE_KEYBOARD,
    SELECT_KEYBOARD,
    COMPLETE
}

data class SetupState(
    val coreRequiredStep: SetupRepository.RequiredStep = SetupRepository.RequiredStep.DOWNLOAD_MODELS,
    val isSplashComplete: Boolean = false,
    val isIntroComplete: Boolean = false,
    val destination: SetupDestination = SetupDestination.SPLASH
) : MavericksState

class SetupViewModel(
    initialState: SetupState,
    private val setupRepository: SetupRepository
) : MavericksViewModel<SetupState>(initialState) {

    fun onSplashFinished() {
        setState {
            val updated = copy(isSplashComplete = true)
            updated.copy(destination = computeDestination(updated))
        }
    }

    fun onIntroContinue() {
        setState {
            val updated = copy(isIntroComplete = true)
            updated.copy(destination = computeDestination(updated))
        }
    }

    fun refreshRequiredStep() {
        viewModelScope.launch {
            val requiredStep = withContext(Dispatchers.IO) {
                setupRepository.requiredStep()
            }
            setState {
                val updated = copy(coreRequiredStep = requiredStep)
                updated.copy(destination = computeDestination(updated))
            }
        }
    }

    private fun computeDestination(state: SetupState): SetupDestination {
        if (!state.isSplashComplete) return SetupDestination.SPLASH
        if (!state.isIntroComplete) return SetupDestination.INTRO
        return when (state.coreRequiredStep) {
            SetupRepository.RequiredStep.DOWNLOAD_MODELS -> SetupDestination.DOWNLOAD_MODELS
            SetupRepository.RequiredStep.MIC_PERMISSION -> SetupDestination.MIC_PERMISSION
            SetupRepository.RequiredStep.ENABLE_KEYBOARD -> SetupDestination.ENABLE_KEYBOARD
            SetupRepository.RequiredStep.SELECT_KEYBOARD -> SetupDestination.SELECT_KEYBOARD
            SetupRepository.RequiredStep.COMPLETE -> SetupDestination.COMPLETE
        }
    }

    companion object : MavericksViewModelFactory<SetupViewModel, SetupState> {
        override fun initialState(viewModelContext: ViewModelContext): SetupState {
            val app = viewModelContext.app<VoiceApp>()
            val requiredStep = app.appGraph.setupRepository.requiredStep()
            return SetupState(
                coreRequiredStep = requiredStep,
                destination = SetupDestination.SPLASH
            )
        }

        override fun create(
            viewModelContext: ViewModelContext,
            state: SetupState
        ): SetupViewModel {
            val app = viewModelContext.app<VoiceApp>()
            return SetupViewModel(
                initialState = state,
                setupRepository = app.appGraph.setupRepository
            )
        }
    }
}

@Composable
fun SetupFlowScreen(
    onSetupComplete: () -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val setupViewModel = mavericksViewModel<SetupViewModel, SetupState>()
    val state by setupViewModel.collectAsStateWithLifecycle()

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) {
        setupViewModel.refreshRequiredStep()
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                setupViewModel.refreshRequiredStep()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(state.destination) {
        if (state.destination == SetupDestination.COMPLETE) {
            onSetupComplete()
        }
    }

    when (state.destination) {
        SetupDestination.SPLASH -> SetupStep1SplashScreen(onFinished = setupViewModel::onSplashFinished)
        SetupDestination.INTRO -> SetupStep2IntroScreen(onContinue = setupViewModel::onIntroContinue)
        SetupDestination.DOWNLOAD_MODELS -> SetupStep3ModelsDownloadScreen(
            onModelsReady = setupViewModel::refreshRequiredStep
        )
        SetupDestination.MIC_PERMISSION -> SetupStep4MicPermissionScreen(
            onGrantMic = { permissionLauncher.launch(Manifest.permission.RECORD_AUDIO) }
        )
        SetupDestination.ENABLE_KEYBOARD -> SetupStep5KeyboardEnableScreen(
            onOpenImeSettings = { openImeSettings(context) }
        )
        SetupDestination.SELECT_KEYBOARD -> SetupStep6KeyboardSelectScreen(
            onRequestKeyboardPicker = { showImePicker(context) },
            onDone = setupViewModel::refreshRequiredStep
        )
        SetupDestination.COMPLETE -> Unit
    }
}

private fun openImeSettings(context: Context) {
    val intent = Intent(Settings.ACTION_INPUT_METHOD_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(intent)
}

private fun showImePicker(context: Context) {
    val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
    imm.showInputMethodPicker()
}
