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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle as collectFlowAsStateWithLifecycle
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.voice.di.appGraph
import com.sanogueralorenzo.voice.setup.SetupState
import com.sanogueralorenzo.voice.setup.SetupViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@Composable
fun SettingsFlowScreen() {
    val context = LocalContext.current
    val appContext = remember(context) { context.applicationContext }
    val appGraph = remember(appContext) { appContext.appGraph() }
    val lifecycleOwner = LocalLifecycleOwner.current
    val setupViewModel = mavericksViewModel<SetupViewModel, SetupState>()
    val state by setupViewModel.collectAsStateWithLifecycle()
    val keyboardThemeMode by appGraph.themeRepository.keyboardThemeModeFlow.collectFlowAsStateWithLifecycle()
    val scope = rememberCoroutineScope()

    DisposableEffect(setupViewModel) {
        onDispose { setupViewModel.shutdown() }
    }
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_START || event == Lifecycle.Event.ON_RESUME) {
                setupViewModel.refreshMicPermission()
                setupViewModel.refreshKeyboardStatus()
                setupViewModel.refreshModelReadiness()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(Unit) {
        setupViewModel.refreshMicPermission()
        setupViewModel.refreshKeyboardStatus()
        setupViewModel.refreshModelReadiness()
    }

    SettingsNavHost(
        uiState = state,
        keyboardThemeMode = keyboardThemeMode,
        onSettingsInputChange = { setupViewModel.setSettingsKeyboardTestInput(it) },
        onThemeInputChange = { setupViewModel.setThemeKeyboardTestInput(it) },
        onDownloadPrompt = {
            setupViewModel.startPromptDownload { _ ->
                setupViewModel.refreshModelReadiness()
            }
        },
        onShowImePicker = {
            showImePicker(context)
            scope.launch {
                repeat(10) {
                    delay(250)
                    setupViewModel.refreshKeyboardStatus()
                }
            }
        }
    )
}

private fun showImePicker(context: Context) {
    val imm = context.getSystemService(Context.INPUT_METHOD_SERVICE) as InputMethodManager
    imm.showInputMethodPicker()
}
