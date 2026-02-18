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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.airbnb.mvrx.compose.mavericksViewModel

@Composable
fun SetupFlowScreen(
    onSetupComplete: () -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val setupViewModel = mavericksViewModel<SetupViewModel, SetupUiState>()
    val uiState by setupViewModel.collectAsStateWithLifecycle()
    var allowMobileDataDownloads by rememberSaveable { mutableStateOf(false) }
    var setupSplashCompleted by rememberSaveable { mutableStateOf(false) }

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

    LaunchedEffect(uiState.wifiConnected) {
        if (uiState.wifiConnected) allowMobileDataDownloads = false
    }

    val setupTargetRoute = when (uiState.requiredStep) {
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

    LaunchedEffect(uiState.requiredStep) {
        if (uiState.requiredStep == SetupRepository.RequiredStep.COMPLETE) {
            onSetupComplete()
        }
    }

    if (requiredSetupRoute == null) {
        Box(modifier = Modifier.fillMaxSize())
        return
    }

    SetupStepNavHost(
        requiredRoute = requiredSetupRoute,
        connectedToWifi = uiState.wifiConnected,
        allowMobileDataDownloads = allowMobileDataDownloads,
        uiState = uiState,
        onAllowMobileDataChange = { allowMobileDataDownloads = it },
        onGrantMic = { permissionLauncher.launch(Manifest.permission.RECORD_AUDIO) },
        onOpenImeSettings = { openImeSettings(context) },
        onDownloadModels = { setupViewModel.downloadAllModels() },
        onSplashFinished = { setupSplashCompleted = true },
        onIntroContinue = { setupViewModel.onSetupIntroContinue() }
    )
}

private fun openImeSettings(context: Context) {
    val intent = Intent(Settings.ACTION_INPUT_METHOD_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(intent)
}
