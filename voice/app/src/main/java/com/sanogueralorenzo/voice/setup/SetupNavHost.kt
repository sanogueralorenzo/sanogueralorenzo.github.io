package com.sanogueralorenzo.voice.setup

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Keyboard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.NavHostController
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.di.appGraph

private object MainRoute {
    const val HOME = "home"
    const val SETUP_INTRO = "setup_intro"
    const val SETUP_MIC = "setup_mic"
    const val SETUP_ENABLE_KEYBOARD = "setup_enable_keyboard"
    const val SETUP_CHOOSE_KEYBOARD = "setup_choose_keyboard"
    const val SETUP_MODELS = "setup_models"
    const val ONBOARDING = "onboarding"
    const val PROMPT_BENCHMARKING = "prompt_benchmarking"
    const val CHECK_UPDATES = "check_updates"
    const val SETTINGS = "settings"
    val SETUP_ROUTES = setOf(
        SETUP_INTRO,
        SETUP_MIC,
        SETUP_ENABLE_KEYBOARD,
        SETUP_CHOOSE_KEYBOARD,
        SETUP_MODELS
    )
}

@Composable
@OptIn(ExperimentalMaterial3Api::class)
fun SetupNavHost() {
    val context = LocalContext.current
    val appContext = remember(context) { context.applicationContext }
    val appGraph = remember(appContext) { appContext.appGraph() }
    val setupRepository = remember(appContext, appGraph) { appGraph.setupRepository }
    val lifecycleOwner = LocalLifecycleOwner.current
    val setupViewModel = remember(appContext, appGraph, setupRepository) {
        SetupViewModel(
            initialState = SetupUiState(
                micGranted = false,
                voiceImeEnabled = false,
                voiceImeSelected = false,
                liteRtRewriteEnabled = appGraph.settingsStore.isLiteRtRewriteEnabled()
            ),
            context = appContext,
            settingsStore = appGraph.settingsStore,
            updateChecker = appGraph.modelUpdateChecker,
            setupRepository = setupRepository
        )
    }
    val checkUpdatesViewModel = remember(appContext, appGraph) {
        CheckUpdatesViewModel(
            initialState = CheckUpdatesUiState(),
            context = appContext,
            updateChecker = appGraph.modelUpdateChecker
        )
    }
    val uiState by setupViewModel.collectAsStateWithLifecycle()
    val checkUpdatesUiState by checkUpdatesViewModel.collectAsStateWithLifecycle()
    var keyboardSelectionAssumed by rememberSaveable { mutableStateOf(false) }
    var allowMobileDataDownloads by rememberSaveable { mutableStateOf(false) }
    var setupIntroDismissed by rememberSaveable { mutableStateOf(false) }

    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        setupViewModel.onMicPermissionResult(granted)
    }

    DisposableEffect(setupViewModel) {
        onDispose { setupViewModel.shutdown() }
    }
    DisposableEffect(checkUpdatesViewModel) {
        onDispose { checkUpdatesViewModel.shutdown() }
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_START || event == Lifecycle.Event.ON_RESUME) {
                setupViewModel.refreshMicPermission()
                setupViewModel.refreshKeyboardStatus()
                setupViewModel.refreshNetworkStatus()
                setupViewModel.refreshModelReadiness()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    DisposableEffect(appContext) {
        val connectivityManager = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        if (connectivityManager == null) {
            onDispose { }
        } else {
            val callback = object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    setupViewModel.refreshNetworkStatus()
                }

                override fun onLost(network: Network) {
                    setupViewModel.refreshNetworkStatus()
                }

                override fun onCapabilitiesChanged(network: Network, networkCapabilities: NetworkCapabilities) {
                    setupViewModel.refreshNetworkStatus()
                }
            }
            val request = NetworkRequest.Builder().build()
            runCatching { connectivityManager.registerNetworkCallback(request, callback) }
            onDispose {
                runCatching { connectivityManager.unregisterNetworkCallback(callback) }
            }
        }
    }

    LaunchedEffect(Unit) {
        setupViewModel.refreshMicPermission()
        setupViewModel.refreshKeyboardStatus()
        setupViewModel.refreshNetworkStatus()
        setupViewModel.refreshModelReadiness()
    }

    LaunchedEffect(uiState.micGranted) {
        if (!uiState.micGranted) keyboardSelectionAssumed = false
    }
    LaunchedEffect(uiState.voiceImeEnabled) {
        if (!uiState.voiceImeEnabled) keyboardSelectionAssumed = false
    }
    LaunchedEffect(uiState.connectedToWifi) {
        if (uiState.connectedToWifi) allowMobileDataDownloads = false
    }

    val requiredSetupStep = remember(
        setupIntroDismissed,
        keyboardSelectionAssumed,
        uiState.micGranted,
        uiState.voiceImeEnabled,
        uiState.voiceImeSelected,
        uiState.liteRtReady,
        uiState.moonshineReady,
        uiState.promptReady
    ) {
        setupRepository.requiredStep(
            introDismissed = setupIntroDismissed,
            keyboardSelectionAssumed = keyboardSelectionAssumed
        )
    }
    val requiredSetupRoute = when (requiredSetupStep) {
        SetupRepository.RequiredStep.INTRO -> MainRoute.SETUP_INTRO
        SetupRepository.RequiredStep.MIC_PERMISSION -> MainRoute.SETUP_MIC
        SetupRepository.RequiredStep.ENABLE_KEYBOARD -> MainRoute.SETUP_ENABLE_KEYBOARD
        SetupRepository.RequiredStep.CHOOSE_KEYBOARD -> MainRoute.SETUP_CHOOSE_KEYBOARD
        SetupRepository.RequiredStep.DOWNLOAD_MODELS -> MainRoute.SETUP_MODELS
        SetupRepository.RequiredStep.COMPLETE -> null
    }
    val startDestination = requiredSetupRoute ?: MainRoute.HOME
    val navController = rememberNavController()
    val backStackEntry = navController.currentBackStackEntryAsState().value
    val currentRoute = backStackEntry?.destination?.route
    val isSetupRoute = currentRoute != null && currentRoute in MainRoute.SETUP_ROUTES
    val canGoBack = currentRoute != null && currentRoute != MainRoute.HOME && !isSetupRoute
    val topBarTitle = when (currentRoute) {
        MainRoute.SETUP_INTRO -> stringResource(R.string.main_title_voice_keyboard)
        MainRoute.SETUP_MIC -> stringResource(R.string.main_title_voice_keyboard)
        MainRoute.SETUP_ENABLE_KEYBOARD -> stringResource(R.string.main_title_voice_keyboard)
        MainRoute.SETUP_CHOOSE_KEYBOARD -> stringResource(R.string.main_title_voice_keyboard)
        MainRoute.SETUP_MODELS -> stringResource(R.string.main_title_voice_keyboard)
        MainRoute.ONBOARDING -> stringResource(R.string.onboarding_section_title)
        MainRoute.PROMPT_BENCHMARKING -> stringResource(R.string.prompt_benchmark_section_title)
        MainRoute.CHECK_UPDATES -> stringResource(R.string.settings_updates_title)
        MainRoute.SETTINGS -> stringResource(R.string.settings_section_title)
        else -> stringResource(R.string.main_title_voice_keyboard)
    }

    LaunchedEffect(requiredSetupRoute, currentRoute) {
        if (requiredSetupRoute != null && currentRoute != requiredSetupRoute) {
            navController.navigateClearingBackStack(requiredSetupRoute)
            return@LaunchedEffect
        }
        if (requiredSetupRoute == null && currentRoute != null && currentRoute in MainRoute.SETUP_ROUTES) {
            navController.navigateClearingBackStack(MainRoute.HOME)
        }
    }

    val actions = SetupActions(
        onOpenOnboarding = { navController.navigate(MainRoute.ONBOARDING) },
        onOpenPromptBenchmarking = { navController.navigate(MainRoute.PROMPT_BENCHMARKING) },
        onOpenCheckUpdates = { navController.navigate(MainRoute.CHECK_UPDATES) },
        onOpenSettings = { navController.navigate(MainRoute.SETTINGS) },
        onGrantMic = { permissionLauncher.launch(Manifest.permission.RECORD_AUDIO) },
        onOpenImeSettings = { openImeSettings(context) },
        onShowImePicker = {
            showImePicker(context)
            keyboardSelectionAssumed = true
        }
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        text = topBarTitle,
                        fontWeight = FontWeight.SemiBold
                    )
                },
                navigationIcon = {
                    if (canGoBack) {
                        IconButton(onClick = { navController.popBackStack() }) {
                            Icon(
                                imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                                contentDescription = stringResource(R.string.main_back)
                            )
                        }
                    }
                },
                actions = {
                    if (!isSetupRoute) {
                        IconButton(onClick = actions.onShowImePicker) {
                            Icon(
                                imageVector = Icons.Rounded.Keyboard,
                                contentDescription = stringResource(R.string.setup_select_keyboard)
                            )
                        }
                    }
                }
            )
        },
        bottomBar = {
            if (currentRoute == MainRoute.HOME) {
                KeyboardTestBar(
                    value = uiState.keyboardTestInput,
                    onValueChange = { setupViewModel.setKeyboardTestInput(it) }
                )
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = startDestination,
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            composable(MainRoute.HOME) {
                HomeScreen(
                    onOpenOnboarding = actions.onOpenOnboarding,
                    onOpenPromptBenchmarking = actions.onOpenPromptBenchmarking,
                    onOpenCheckUpdates = actions.onOpenCheckUpdates,
                    onOpenSettings = actions.onOpenSettings
                )
            }

            composable(MainRoute.SETUP_INTRO) {
                SetupIntroScreen(
                    onContinue = { setupIntroDismissed = true }
                )
            }

            composable(MainRoute.SETUP_MIC) {
                SetupMicPermissionScreen(
                    onGrantMic = actions.onGrantMic
                )
            }

            composable(MainRoute.SETUP_ENABLE_KEYBOARD) {
                SetupEnableKeyboardScreen(
                    onOpenImeSettings = actions.onOpenImeSettings
                )
            }

            composable(MainRoute.SETUP_CHOOSE_KEYBOARD) {
                SetupChooseKeyboardScreen(
                    onShowImePicker = actions.onShowImePicker
                )
            }

            composable(MainRoute.SETUP_MODELS) {
                SetupDownloadModelsScreen(
                    connectedToWifi = uiState.connectedToWifi,
                    allowMobileDataDownloads = allowMobileDataDownloads,
                    liteRtReady = uiState.liteRtReady,
                    moonshineReady = uiState.moonshineReady,
                    promptReady = uiState.promptReady,
                    liteRtDownloading = uiState.liteRtDownloading,
                    moonshineDownloading = uiState.moonshineDownloading,
                    promptDownloading = uiState.promptDownloading,
                    liteRtProgress = uiState.liteRtProgress,
                    moonshineProgress = uiState.moonshineProgress,
                    promptProgress = uiState.promptProgress,
                    promptVersion = uiState.promptVersion,
                    modelMessage = uiState.modelMessage,
                    updatesMessage = uiState.updatesMessage,
                    onAllowMobileDataChange = { allowMobileDataDownloads = it },
                    onDownloadModels = { setupViewModel.downloadAllModels() }
                )
            }

            composable(MainRoute.ONBOARDING) {
                OnboardingTutorialScreen(
                    onDone = {
                        navController.navigate(MainRoute.HOME) {
                            popUpTo(MainRoute.HOME) { inclusive = true }
                            launchSingleTop = true
                        }
                    }
                )
            }

            composable(MainRoute.PROMPT_BENCHMARKING) {
                PromptBenchmarkingScreen()
            }

            composable(MainRoute.SETTINGS) {
                SettingsScreen(
                    rewriteEnabled = uiState.liteRtRewriteEnabled,
                    onRewriteEnabledChange = { enabled ->
                        setupViewModel.setLiteRtRewriteEnabled(enabled)
                    }
                )
            }

            composable(MainRoute.CHECK_UPDATES) {
                CheckUpdatesScreen(
                    updatesRunning = checkUpdatesUiState.updatesRunning,
                    updatesMessage = checkUpdatesUiState.updatesMessage,
                    modelMessage = checkUpdatesUiState.modelMessage,
                    onCheckUpdates = { checkUpdatesViewModel.checkForUpdates() }
                )
            }
        }
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

private fun NavHostController.navigateClearingBackStack(route: String) {
    while (popBackStack()) {
        // Keep popping until the stack is empty so setup/home can be enforced after runtime changes.
    }
    navigate(route) {
        launchSingleTop = true
    }
}
