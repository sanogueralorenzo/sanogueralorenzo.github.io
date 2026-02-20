package com.sanogueralorenzo.voice.setup

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
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
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.VoiceApp
import com.sanogueralorenzo.voice.ui.components.VoiceInput
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

data class SetupStep6KeyboardSelectState(
    val value: String = "",
    val voiceImeSelected: Boolean = false
) : MavericksState

class SetupStep6KeyboardSelectViewModel(
    initialState: SetupStep6KeyboardSelectState,
    private val setupRepository: SetupRepository
) : MavericksViewModel<SetupStep6KeyboardSelectState>(initialState) {

    fun refreshKeyboardStatus() {
        val keyboardStatus = setupRepository.keyboardStatus()
        setState { copy(voiceImeSelected = keyboardStatus.selected) }
    }

    fun onValueChange(value: String) {
        setState { copy(value = value) }
    }

    fun completeSetup(onComplete: () -> Unit) {
        viewModelScope.launch {
            setupRepository.setSetupComplete(complete = true)
            onComplete()
        }
    }

    companion object : MavericksViewModelFactory<SetupStep6KeyboardSelectViewModel, SetupStep6KeyboardSelectState> {
        override fun create(
            viewModelContext: ViewModelContext,
            state: SetupStep6KeyboardSelectState
        ): SetupStep6KeyboardSelectViewModel {
            val app = viewModelContext.app<VoiceApp>()
            return SetupStep6KeyboardSelectViewModel(
                initialState = state,
                setupRepository = app.appGraph.setupRepository
            )
        }
    }
}

@Composable
fun SetupStep6KeyboardSelectScreen(
    onRequestKeyboardPicker: () -> Unit,
    onDone: () -> Unit
) {
    val lifecycleOwner = LocalLifecycleOwner.current
    val viewModel = mavericksViewModel<SetupStep6KeyboardSelectViewModel, SetupStep6KeyboardSelectState>()
    val state by viewModel.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_START || event == Lifecycle.Event.ON_RESUME) {
                viewModel.refreshKeyboardStatus()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(Unit) {
        viewModel.refreshKeyboardStatus()
    }

    SetupStepScaffold(
        title = stringResource(R.string.setup_step_select_keyboard),
        body = {
            Text(
                text = stringResource(R.string.setup_select_keyboard_step_message),
                style = MaterialTheme.typography.bodyMedium
            )
        },
        actions = {
            VoiceInput(
                value = state.value,
                onValueChange = viewModel::onValueChange,
                voiceImeSelected = state.voiceImeSelected,
                onRequestKeyboardPicker = {
                    onRequestKeyboardPicker()
                    scope.launch {
                        repeat(10) {
                            delay(250)
                            viewModel.refreshKeyboardStatus()
                        }
                    }
                },
                autoFocusOnResume = true
            )
            Spacer(modifier = Modifier.height(16.dp))
            Button(
                onClick = {
                    viewModel.completeSetup(onComplete = onDone)
                },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = stringResource(R.string.setup_done))
            }
        }
    )
}
