package com.sanogueralorenzo.voice.setup

import android.Manifest
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
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

enum class SetupFlowStep {
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
    val splashCompleted: Boolean = false,
    val introCompleted: Boolean = false,
    val requiredStep: SetupFlowStep = SetupFlowStep.SPLASH
) : MavericksState

class SetupViewModel(
    initialState: SetupState,
    private val setupRepository: SetupRepository
) : MavericksViewModel<SetupState>(initialState) {

    init {
        refreshRequiredStep()
    }

    fun onSplashFinished() {
        setState {
            val updated = copy(splashCompleted = true)
            updated.copy(requiredStep = computeFlowStep(updated))
        }
    }

    fun onIntroContinue() {
        setState {
            val updated = copy(introCompleted = true)
            updated.copy(requiredStep = computeFlowStep(updated))
        }
    }

    fun refreshRequiredStep() {
        viewModelScope.launch {
            val requiredStep = withContext(Dispatchers.IO) {
                setupRepository.requiredStep()
            }
            setState {
                val updated = copy(coreRequiredStep = requiredStep)
                updated.copy(requiredStep = computeFlowStep(updated))
            }
        }
    }

    private fun computeFlowStep(state: SetupState): SetupFlowStep {
        if (!state.splashCompleted) return SetupFlowStep.SPLASH
        if (!state.introCompleted) return SetupFlowStep.INTRO
        return when (state.coreRequiredStep) {
            SetupRepository.RequiredStep.DOWNLOAD_MODELS -> SetupFlowStep.DOWNLOAD_MODELS
            SetupRepository.RequiredStep.MIC_PERMISSION -> SetupFlowStep.MIC_PERMISSION
            SetupRepository.RequiredStep.ENABLE_KEYBOARD -> SetupFlowStep.ENABLE_KEYBOARD
            SetupRepository.RequiredStep.SELECT_KEYBOARD -> SetupFlowStep.SELECT_KEYBOARD
            SetupRepository.RequiredStep.COMPLETE -> SetupFlowStep.COMPLETE
        }
    }

    companion object : MavericksViewModelFactory<SetupViewModel, SetupState> {
        override fun initialState(viewModelContext: ViewModelContext): SetupState {
            val app = viewModelContext.app<VoiceApp>()
            val requiredStep = app.appGraph.setupRepository.requiredStep()
            return SetupState(
                coreRequiredStep = requiredStep,
                requiredStep = SetupFlowStep.SPLASH
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
            if (event == Lifecycle.Event.ON_START || event == Lifecycle.Event.ON_RESUME) {
                setupViewModel.refreshRequiredStep()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(Unit) {
        setupViewModel.refreshRequiredStep()
    }

    val requiredSetupRoute = when (state.requiredStep) {
        SetupFlowStep.SPLASH -> SetupRoute.SETUP_SPLASH
        SetupFlowStep.INTRO -> SetupRoute.SETUP_INTRO
        SetupFlowStep.MIC_PERMISSION -> SetupRoute.SETUP_MIC
        SetupFlowStep.ENABLE_KEYBOARD -> SetupRoute.SETUP_ENABLE_KEYBOARD
        SetupFlowStep.DOWNLOAD_MODELS -> SetupRoute.SETUP_MODELS
        SetupFlowStep.SELECT_KEYBOARD -> SetupRoute.SETUP_SELECT_KEYBOARD
        SetupFlowStep.COMPLETE -> null
    }

    LaunchedEffect(state.requiredStep) {
        if (state.requiredStep == SetupFlowStep.COMPLETE) {
            onSetupComplete()
        }
    }

    if (requiredSetupRoute == null) {
        Box(modifier = Modifier.fillMaxSize())
        return
    }

    SetupStepNavHost(
        requiredRoute = requiredSetupRoute,
        onGrantMic = { permissionLauncher.launch(Manifest.permission.RECORD_AUDIO) },
        onOpenImeSettings = { openImeSettings(context) },
        onShowImePicker = { showImePicker(context) },
        onSplashFinished = { setupViewModel.onSplashFinished() },
        onIntroContinue = { setupViewModel.onIntroContinue() },
        onSetupStateChanged = { setupViewModel.refreshRequiredStep() }
    )
}

private fun openImeSettings(context: Context) {
    val intent = Intent(Settings.ACTION_INPUT_METHOD_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(intent)
}

private fun showImePicker(context: Context) {
    val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
    imm.showInputMethodPicker()
}
