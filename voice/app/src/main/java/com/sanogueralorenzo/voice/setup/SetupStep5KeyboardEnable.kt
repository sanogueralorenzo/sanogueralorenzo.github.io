package com.sanogueralorenzo.voice.setup

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
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
import com.airbnb.mvrx.withState
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.VoiceApp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

enum class KeyboardSetupStage {
    ENABLE_KEYBOARD,
    SELECT_KEYBOARD,
    READY
}

data class SetupStep5KeyboardSetupState(
    val keyboardEnabled: Boolean = false,
    val keyboardSelected: Boolean = false,
    val setupCompletionInProgress: Boolean = false,
    val setupCompleted: Boolean = false
) : MavericksState {
    val stage: KeyboardSetupStage
        get() = when {
            !keyboardEnabled -> KeyboardSetupStage.ENABLE_KEYBOARD
            !keyboardSelected -> KeyboardSetupStage.SELECT_KEYBOARD
            else -> KeyboardSetupStage.READY
        }
}

class SetupStep5KeyboardSetupViewModel(
    initialState: SetupStep5KeyboardSetupState,
    private val setupRepository: SetupRepository
) : MavericksViewModel<SetupStep5KeyboardSetupState>(initialState) {

    fun refreshKeyboardStatus() {
        val keyboardStatus = setupRepository.keyboardStatus()
        setState {
            copy(
                keyboardEnabled = keyboardStatus.enabled,
                keyboardSelected = keyboardStatus.selected
            )
        }
        if (keyboardStatus.selected) {
            markSetupCompleteIfNeeded()
        }
    }

    fun markSetupCompleteIfNeeded() {
        val shouldComplete = withState(this) { state ->
            state.keyboardSelected && !state.setupCompletionInProgress && !state.setupCompleted
        }
        if (!shouldComplete) return

        viewModelScope.launch {
            setState { copy(setupCompletionInProgress = true) }
            setupRepository.setSetupComplete(complete = true)
            setState {
                copy(
                    setupCompletionInProgress = false,
                    setupCompleted = true
                )
            }
        }
    }

    companion object : MavericksViewModelFactory<SetupStep5KeyboardSetupViewModel, SetupStep5KeyboardSetupState> {
        override fun create(
            viewModelContext: ViewModelContext,
            state: SetupStep5KeyboardSetupState
        ): SetupStep5KeyboardSetupViewModel {
            val app = viewModelContext.app<VoiceApp>()
            return SetupStep5KeyboardSetupViewModel(
                initialState = state,
                setupRepository = app.appGraph.setupRepository
            )
        }
    }
}

@Composable
fun SetupStep5KeyboardSetupScreen(
    onOpenImeSettings: () -> Unit,
    onRequestKeyboardPicker: () -> Unit,
    onDone: () -> Unit
) {
    val lifecycleOwner = LocalLifecycleOwner.current
    val viewModel = mavericksViewModel<SetupStep5KeyboardSetupViewModel, SetupStep5KeyboardSetupState>()
    val state by viewModel.collectAsStateWithLifecycle()

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                viewModel.refreshKeyboardStatus()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(Unit) {
        viewModel.refreshKeyboardStatus()
    }

    LaunchedEffect(state.keyboardSelected) {
        if (state.keyboardSelected) {
            viewModel.markSetupCompleteIfNeeded()
        }
    }

    LaunchedEffect(state.setupCompleted) {
        if (state.setupCompleted) {
            onDone()
        }
    }

    // Keep checking selection while the system keyboard picker is up/opened.
    // This guarantees auto-advance even if user takes longer than a short fixed polling window.
    LaunchedEffect(state.stage, state.setupCompleted) {
        if (state.stage != KeyboardSetupStage.SELECT_KEYBOARD || state.setupCompleted) return@LaunchedEffect
        while (true) {
            delay(500)
            viewModel.refreshKeyboardStatus()
        }
    }

    val bodyText = when (state.stage) {
        KeyboardSetupStage.ENABLE_KEYBOARD -> stringResource(R.string.setup_enable_keyboard_intro)
        KeyboardSetupStage.SELECT_KEYBOARD -> stringResource(R.string.setup_select_keyboard_step_message)
        KeyboardSetupStage.READY -> stringResource(R.string.setup_keyboard_ready_continuing)
    }

    SetupStepScaffold(
        title = stringResource(R.string.setup_step_enable_keyboard),
        body = {
            Text(
                text = bodyText,
                style = MaterialTheme.typography.bodyMedium
            )
        },
        actions = {
            Button(
                onClick = {
                    when (state.stage) {
                        KeyboardSetupStage.ENABLE_KEYBOARD -> onOpenImeSettings()
                        KeyboardSetupStage.SELECT_KEYBOARD -> onRequestKeyboardPicker()
                        KeyboardSetupStage.READY -> Unit
                    }
                },
                enabled = !state.setupCompletionInProgress && state.stage != KeyboardSetupStage.READY,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = stringResource(R.string.setup_continue))
            }
        }
    )
}
