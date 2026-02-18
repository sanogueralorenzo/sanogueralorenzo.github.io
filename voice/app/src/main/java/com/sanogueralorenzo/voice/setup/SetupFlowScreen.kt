package com.sanogueralorenzo.voice.setup

import android.Manifest
import android.content.Context
import android.content.Intent
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle as collectFlowAsStateWithLifecycle
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.airbnb.mvrx.compose.mavericksViewModel
import com.sanogueralorenzo.voice.di.appGraph

@Composable
fun SetupFlowScreen(
    onSetupComplete: () -> Unit
) {
    val context = LocalContext.current
    val appContext = remember(context) { context.applicationContext }
    val appGraph = remember(appContext) { appContext.appGraph() }
    val setupRepository = remember(appGraph) { appGraph.setupRepository }
    val lifecycleOwner = LocalLifecycleOwner.current
    val setupViewModel = mavericksViewModel<SetupViewModel, SetupUiState>()
    val uiState by setupViewModel.collectAsStateWithLifecycle()
    val connectedToWifi by setupRepository.wifiConnected.collectFlowAsStateWithLifecycle()
    var allowMobileDataDownloads by rememberSaveable { mutableStateOf(false) }
    var setupSplashCompleted by rememberSaveable { mutableStateOf(false) }
    var setupIntroDismissed by rememberSaveable { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        setupViewModel.onMicPermissionResult(granted)
    }

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

    LaunchedEffect(connectedToWifi) {
        if (connectedToWifi) allowMobileDataDownloads = false
    }

    val requiredStep = remember(
        setupIntroDismissed,
        uiState.micGranted,
        uiState.voiceImeEnabled,
        uiState.liteRtReady,
        uiState.moonshineReady,
        uiState.promptReady
    ) {
        setupRepository.requiredStep(
            introDismissed = setupIntroDismissed
        )
    }
    val setupTargetRoute = when (requiredStep) {
        SetupRepository.RequiredStep.INTRO -> SetupRoute.SETUP_INTRO
        SetupRepository.RequiredStep.MIC_PERMISSION -> SetupRoute.SETUP_MIC
        SetupRepository.RequiredStep.ENABLE_KEYBOARD -> SetupRoute.SETUP_ENABLE_KEYBOARD
        SetupRepository.RequiredStep.DOWNLOAD_MODELS -> SetupRoute.SETUP_MODELS
        SetupRepository.RequiredStep.COMPLETE -> null
    }
    val requiredSetupRoute = if (setupTargetRoute != null && !setupSplashCompleted) {
        SetupRoute.SETUP_SPLASH
    } else {
        setupTargetRoute
    }

    LaunchedEffect(requiredStep) {
        if (requiredStep == SetupRepository.RequiredStep.COMPLETE) {
            onSetupComplete()
        }
    }

    if (requiredSetupRoute == null) {
        Box(modifier = Modifier.fillMaxSize())
        return
    }

    SetupNavHost(
        requiredRoute = requiredSetupRoute,
        connectedToWifi = connectedToWifi,
        allowMobileDataDownloads = allowMobileDataDownloads,
        uiState = uiState,
        onAllowMobileDataChange = { allowMobileDataDownloads = it },
        onGrantMic = { permissionLauncher.launch(Manifest.permission.RECORD_AUDIO) },
        onOpenImeSettings = { openImeSettings(context) },
        onDownloadModels = { setupViewModel.downloadAllModels() },
        onSplashFinished = { setupSplashCompleted = true },
        onIntroContinue = { setupIntroDismissed = true }
    )
}

private fun openImeSettings(context: Context) {
    val intent = Intent(Settings.ACTION_INPUT_METHOD_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(intent)
}
