package com.sanogueralorenzo.voice.setup

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.provider.Settings
import android.view.inputmethod.InputMethodManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Keyboard
import androidx.compose.material3.Button
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelDownloadResult
import com.sanogueralorenzo.voice.models.ModelDownloader
import com.sanogueralorenzo.voice.models.ModelSpec
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.models.ModelUpdateChecker
import com.sanogueralorenzo.voice.settings.VoiceSettingsStore
import com.sanogueralorenzo.voice.ui.theme.VoiceTheme
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            VoiceTheme {
                VoiceKeyboardSetupRoot()
            }
        }
    }
}

private object MainRoute {
    const val HOME = "home"
    const val SETUP = "setup"
    const val MODELS = "models"
    const val ONBOARDING = "onboarding"
    const val CALIBRATION = "calibration"
    const val SETTINGS = "settings"
}

@Composable
@OptIn(ExperimentalMaterial3Api::class)
private fun VoiceKeyboardSetupRoot() {
    val context = LocalContext.current
    val appContext = remember(context) { context.applicationContext }

    var micGranted by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECORD_AUDIO
            ) == PackageManager.PERMISSION_GRANTED
        )
    }
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        micGranted = granted
    }

    val downloader = remember(appContext) { ModelDownloader(appContext) }
    val updateChecker = remember(appContext) { ModelUpdateChecker(appContext) }
    val settingsStore = remember(appContext) { VoiceSettingsStore(appContext) }
    val scope = rememberCoroutineScope()
    DisposableEffect(downloader) {
        onDispose { downloader.shutdown() }
    }

    var liteRtReady by remember { mutableStateOf(false) }
    var moonshineReady by remember { mutableStateOf(false) }
    var liteRtProgress by remember { mutableStateOf(0) }
    var moonshineProgress by remember { mutableStateOf(0) }
    var liteRtDownloading by remember { mutableStateOf(false) }
    var moonshineDownloading by remember { mutableStateOf(false) }
    var updatesRunning by remember { mutableStateOf(false) }
    var modelMessage by remember { mutableStateOf<String?>(null) }
    var updatesMessage by remember { mutableStateOf<String?>(null) }
    var keyboardTestInput by rememberSaveable { mutableStateOf("") }
    var liteRtRewriteEnabled by rememberSaveable {
        mutableStateOf(settingsStore.isLiteRtRewriteEnabled())
    }
    var customInstructions by rememberSaveable {
        mutableStateOf(settingsStore.customInstructions())
    }

    val lifecycleOwner = LocalLifecycleOwner.current

    fun isAnyDownloading(): Boolean {
        return liteRtDownloading ||
            moonshineDownloading ||
            updatesRunning
    }

    fun refreshModelReadiness() {
        scope.launch {
            val liteRt = withContext(Dispatchers.IO) {
                ModelStore.isModelReadyStrict(appContext, ModelCatalog.liteRtLm)
            }
            val moonshine = withContext(Dispatchers.IO) {
                ModelCatalog.moonshineMediumStreamingSpecs.all {
                    ModelStore.isModelReadyStrict(appContext, it)
                }
            }
            liteRtReady = liteRt
            moonshineReady = moonshine
        }
    }

    fun checkForModelUpdates() {
        if (isAnyDownloading()) return
        updatesMessage = context.getString(R.string.models_check_updates_running)
        updatesRunning = true
        scope.launch {
            try {
                val allSpecs = buildList {
                    add(ModelCatalog.liteRtLm)
                    addAll(ModelCatalog.moonshineMediumStreamingSpecs)
                }
                when (val check = withContext(Dispatchers.IO) { updateChecker.check(allSpecs) }) {
                    is ModelUpdateChecker.CheckResult.UpToDate -> {
                        updatesMessage = context.getString(R.string.models_check_updates_none)
                    }

                    is ModelUpdateChecker.CheckResult.Unreachable -> {
                        updatesMessage = context.getString(R.string.models_check_updates_unreachable)
                    }

                    is ModelUpdateChecker.CheckResult.UpdatesAvailable -> {
                        updatesMessage = context.getString(
                            R.string.models_check_updates_downloading,
                            check.updates.size
                        )
                        var applied = 0
                        var firstFailure: String? = null
                        for (candidate in check.updates) {
                            val result = downloadSpecAwait(
                                downloader = downloader,
                                spec = candidate.spec,
                                force = true
                            )
                            val ok = result is ModelDownloadResult.Success ||
                                result is ModelDownloadResult.AlreadyAvailable
                            if (ok) {
                                applied += 1
                                withContext(Dispatchers.IO) { updateChecker.markApplied(candidate) }
                            } else if (firstFailure == null) {
                                firstFailure = downloadResultMessage(context, candidate.spec, result)
                            }
                        }
                        if (!firstFailure.isNullOrBlank()) {
                            modelMessage = firstFailure
                        }
                        updatesMessage = if (applied == check.updates.size) {
                            context.getString(
                                R.string.models_check_updates_applied,
                                applied
                            )
                        } else {
                            context.getString(
                                R.string.models_check_updates_partial,
                                applied,
                                check.updates.size
                            )
                        }
                    }
                }
                refreshModelReadiness()
            } finally {
                updatesRunning = false
            }
        }
    }

    fun startLiteRtDownload(onComplete: (Boolean) -> Unit = {}) {
        if (liteRtReady || isAnyDownloading()) {
            onComplete(liteRtReady)
            return
        }
        liteRtDownloading = true
        liteRtProgress = 0
        modelMessage = null
        downloader.download(
            spec = ModelCatalog.liteRtLm,
            onProgress = { percent -> liteRtProgress = percent },
            onComplete = { result ->
                liteRtDownloading = false
                val ready = result is ModelDownloadResult.Success ||
                    result is ModelDownloadResult.AlreadyAvailable
                liteRtReady = ready
                modelMessage = if (ready) null else downloadResultMessage(context, ModelCatalog.liteRtLm, result)
                if (!ready) refreshModelReadiness()
                onComplete(ready)
            }
        )
    }

    fun startModelPackDownload(
        specs: List<ModelSpec>,
        ready: Boolean,
        setDownloading: (Boolean) -> Unit,
        setProgress: (Int) -> Unit,
        setReady: (Boolean) -> Unit,
        onComplete: (Boolean) -> Unit = {}
    ) {
        if (ready || isAnyDownloading()) {
            onComplete(ready)
            return
        }
        if (specs.isEmpty()) {
            setReady(false)
            onComplete(false)
            return
        }

        setDownloading(true)
        setProgress(0)
        modelMessage = null
        val total = specs.size

        fun runNext(index: Int) {
            if (index >= total) {
                setDownloading(false)
                setProgress(100)
                setReady(true)
                onComplete(true)
                return
            }
            val spec = specs[index]
            downloader.download(
                spec = spec,
                onProgress = { percent ->
                    val overall = ((index * 100f) + percent.toFloat()) / total.toFloat()
                    setProgress(overall.toInt().coerceIn(0, 100))
                },
                onComplete = { result ->
                    val success = result is ModelDownloadResult.Success ||
                        result is ModelDownloadResult.AlreadyAvailable
                    if (!success) {
                        setDownloading(false)
                        setReady(false)
                        modelMessage = downloadResultMessage(context, spec, result)
                        onComplete(false)
                        return@download
                    }
                    runNext(index + 1)
                }
            )
        }

        runNext(0)
    }

    fun startMoonshineDownload(onComplete: (Boolean) -> Unit = {}) {
        startModelPackDownload(
            specs = ModelCatalog.moonshineMediumStreamingSpecs,
            ready = moonshineReady,
            setDownloading = { moonshineDownloading = it },
            setProgress = { moonshineProgress = it },
            setReady = { moonshineReady = it },
            onComplete = onComplete
        )
    }

    fun downloadAllModels() {
        if (liteRtReady && moonshineReady) {
            modelMessage = context.getString(R.string.setup_download_all_already_ready)
            return
        }
        fun runMoonshine() {
            if (moonshineReady) {
                modelMessage = context.getString(R.string.setup_download_all_completed)
                refreshModelReadiness()
                return
            }
            startMoonshineDownload { success ->
                if (!success) return@startMoonshineDownload
                modelMessage = context.getString(R.string.setup_download_all_completed)
                refreshModelReadiness()
            }
        }
        if (liteRtReady) {
            runMoonshine()
        } else {
            startLiteRtDownload { success ->
                if (!success) return@startLiteRtDownload
                runMoonshine()
            }
        }
    }

    DisposableEffect(lifecycleOwner, context) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                micGranted = ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.RECORD_AUDIO
                ) == PackageManager.PERMISSION_GRANTED
                refreshModelReadiness()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(Unit) {
        refreshModelReadiness()
    }

    val navController = rememberNavController()
    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentRoute = backStackEntry?.destination?.route
    val canGoBack = currentRoute != MainRoute.HOME
    val topBarTitle = when (currentRoute) {
        MainRoute.SETUP -> stringResource(R.string.setup_section_title)
        MainRoute.MODELS -> stringResource(R.string.models_section_title)
        MainRoute.ONBOARDING -> stringResource(R.string.onboarding_section_title)
        MainRoute.CALIBRATION -> stringResource(R.string.calibration_section_title)
        MainRoute.SETTINGS -> stringResource(R.string.settings_section_title)
        else -> stringResource(R.string.main_title_voice_keyboard)
    }

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
                    IconButton(onClick = { showImePicker(context) }) {
                        Icon(
                            imageVector = Icons.Rounded.Keyboard,
                            contentDescription = stringResource(R.string.setup_select_keyboard)
                        )
                    }
                }
            )
        },
        bottomBar = {
            if (currentRoute == MainRoute.HOME) {
                KeyboardTestBar(
                    value = keyboardTestInput,
                    onValueChange = { keyboardTestInput = it }
                )
            }
        }
    ) { innerPadding ->
        NavHost(
            navController = navController,
            startDestination = MainRoute.HOME,
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            composable(MainRoute.HOME) {
                HomeScreen(
                    onOpenSetup = { navController.navigate(MainRoute.SETUP) },
                    onOpenModels = { navController.navigate(MainRoute.MODELS) },
                    onOpenOnboarding = { navController.navigate(MainRoute.ONBOARDING) },
                    onOpenCalibration = { navController.navigate(MainRoute.CALIBRATION) },
                    onOpenSettings = { navController.navigate(MainRoute.SETTINGS) }
                )
            }

            composable(MainRoute.SETUP) {
                SetupScreen(
                    micGranted = micGranted,
                    onGrantMic = { permissionLauncher.launch(Manifest.permission.RECORD_AUDIO) },
                    onOpenImeSettings = { openImeSettings(context) },
                    onShowImePicker = { showImePicker(context) }
                )
            }

            composable(MainRoute.MODELS) {
                ModelsScreen(
                    liteRtReady = liteRtReady,
                    moonshineReady = moonshineReady,
                    liteRtDownloading = liteRtDownloading,
                    moonshineDownloading = moonshineDownloading,
                    liteRtProgress = liteRtProgress,
                    moonshineProgress = moonshineProgress,
                    downloadMessage = modelMessage,
                    updatesMessage = updatesMessage,
                    onDownloadAll = { downloadAllModels() },
                    onDownloadLiteRt = { startLiteRtDownload() },
                    onDownloadMoonshine = { startMoonshineDownload() },
                    onCheckUpdates = { checkForModelUpdates() },
                    actionsEnabled = !isAnyDownloading()
                )
            }

            composable(MainRoute.ONBOARDING) {
                OnboardingScreen(
                    onOpenSetup = { navController.navigate(MainRoute.SETUP) },
                    onOpenModels = { navController.navigate(MainRoute.MODELS) },
                    onShowImePicker = { showImePicker(context) }
                )
            }

            composable(MainRoute.CALIBRATION) {
                CalibrationScreen(
                    micGranted = micGranted,
                    modelsReady = liteRtReady && moonshineReady,
                    onShowImePicker = { showImePicker(context) },
                    onOpenImeSettings = { openImeSettings(context) }
                )
            }

            composable(MainRoute.SETTINGS) {
                SettingsScreen(
                    rewriteEnabled = liteRtRewriteEnabled,
                    customInstructions = customInstructions,
                    onRewriteEnabledChange = { enabled ->
                        liteRtRewriteEnabled = enabled
                        settingsStore.setLiteRtRewriteEnabled(enabled)
                    },
                    onCustomInstructionsChange = { value ->
                        customInstructions = value.take(VoiceSettingsStore.MAX_CUSTOM_INSTRUCTIONS_CHARS)
                        settingsStore.setCustomInstructions(customInstructions)
                    }
                )
            }
        }
    }
}

@Composable
private fun KeyboardTestBar(
    value: String,
    onValueChange: (String) -> Unit
) {
    ElevatedCard(
        modifier = Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .padding(horizontal = 12.dp, vertical = 8.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Text(
                text = stringResource(R.string.home_keyboard_test_title),
                style = MaterialTheme.typography.titleSmall
            )
            OutlinedTextField(
                value = value,
                onValueChange = onValueChange,
                modifier = Modifier.fillMaxWidth(),
                minLines = 2,
                maxLines = 4,
                placeholder = { Text(text = stringResource(R.string.home_keyboard_test_placeholder)) }
            )
        }
    }
}

@Composable
private fun HomeScreen(
    onOpenSetup: () -> Unit,
    onOpenModels: () -> Unit,
    onOpenOnboarding: () -> Unit,
    onOpenCalibration: () -> Unit,
    onOpenSettings: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        SectionCard(
            title = stringResource(R.string.home_section_setup_title),
            description = stringResource(R.string.home_section_setup_description),
            onClick = onOpenSetup
        )
        SectionCard(
            title = stringResource(R.string.home_section_models_title),
            description = stringResource(R.string.home_section_models_description),
            onClick = onOpenModels
        )
        SectionCard(
            title = stringResource(R.string.home_section_onboarding_title),
            description = stringResource(R.string.home_section_onboarding_description),
            onClick = onOpenOnboarding
        )
        SectionCard(
            title = stringResource(R.string.home_section_calibration_title),
            description = stringResource(R.string.home_section_calibration_description),
            onClick = onOpenCalibration
        )
        SectionCard(
            title = stringResource(R.string.home_section_settings_title),
            description = stringResource(R.string.home_section_settings_description),
            onClick = onOpenSettings
        )
    }
}

@Composable
private fun SettingsScreen(
    rewriteEnabled: Boolean,
    customInstructions: String,
    onRewriteEnabledChange: (Boolean) -> Unit,
    onCustomInstructionsChange: (String) -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = stringResource(R.string.settings_section_title),
            style = MaterialTheme.typography.titleLarge
        )
        Text(
            text = stringResource(R.string.settings_section_description),
            style = MaterialTheme.typography.bodyMedium
        )

        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.settings_rewrite_toggle_title),
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = stringResource(R.string.settings_rewrite_toggle_description),
                    style = MaterialTheme.typography.bodySmall
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = if (rewriteEnabled) {
                            stringResource(R.string.settings_rewrite_enabled)
                        } else {
                            stringResource(R.string.settings_rewrite_disabled)
                        },
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Switch(
                        checked = rewriteEnabled,
                        onCheckedChange = onRewriteEnabledChange
                    )
                }
            }
        }

        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.settings_custom_instructions_title),
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = stringResource(R.string.settings_custom_instructions_description),
                    style = MaterialTheme.typography.bodySmall
                )
                OutlinedTextField(
                    value = customInstructions,
                    onValueChange = onCustomInstructionsChange,
                    modifier = Modifier.fillMaxWidth(),
                    minLines = 4,
                    maxLines = 8,
                    placeholder = {
                        Text(text = stringResource(R.string.settings_custom_instructions_placeholder))
                    }
                )
                Text(
                    text = stringResource(
                        R.string.settings_custom_instructions_counter,
                        customInstructions.length,
                        VoiceSettingsStore.MAX_CUSTOM_INSTRUCTIONS_CHARS
                    ),
                    style = MaterialTheme.typography.bodySmall
                )
            }
        }
    }
}

@Composable
private fun SectionCard(
    title: String,
    description: String,
    onClick: () -> Unit
) {
    ElevatedCard(
        modifier = Modifier.fillMaxWidth(),
        onClick = onClick
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            Text(text = title, style = MaterialTheme.typography.titleMedium)
            Text(text = description, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

@Composable
private fun SetupScreen(
    micGranted: Boolean,
    onGrantMic: () -> Unit,
    onOpenImeSettings: () -> Unit,
    onShowImePicker: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = stringResource(R.string.setup_section_title),
            style = MaterialTheme.typography.titleLarge
        )
        Text(
            text = if (micGranted) {
                stringResource(R.string.setup_mic_granted)
            } else {
                stringResource(R.string.setup_mic_missing)
            },
            style = MaterialTheme.typography.bodyMedium
        )
        Button(onClick = onGrantMic) {
            Text(text = stringResource(R.string.setup_grant_mic))
        }

        Button(onClick = onOpenImeSettings) {
            Text(text = stringResource(R.string.setup_enable_keyboard))
        }
        OutlinedButton(onClick = onShowImePicker) {
            Text(text = stringResource(R.string.setup_select_keyboard))
        }
    }
}

@Composable
private fun OnboardingScreen(
    onOpenSetup: () -> Unit,
    onOpenModels: () -> Unit,
    onShowImePicker: () -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = stringResource(R.string.onboarding_section_title),
            style = MaterialTheme.typography.titleLarge
        )
        Text(
            text = stringResource(R.string.onboarding_intro),
            style = MaterialTheme.typography.bodyMedium
        )
        Text(
            text = stringResource(R.string.onboarding_step_setup),
            style = MaterialTheme.typography.bodyMedium
        )
        Text(
            text = stringResource(R.string.onboarding_step_models),
            style = MaterialTheme.typography.bodyMedium
        )
        Text(
            text = stringResource(R.string.onboarding_step_keyboard),
            style = MaterialTheme.typography.bodyMedium
        )

        Button(onClick = onOpenSetup) {
            Text(text = stringResource(R.string.onboarding_action_open_setup))
        }
        Button(onClick = onOpenModels) {
            Text(text = stringResource(R.string.onboarding_action_open_models))
        }
        OutlinedButton(onClick = onShowImePicker) {
            Text(text = stringResource(R.string.onboarding_action_open_picker))
        }
    }
}

@Composable
private fun CalibrationScreen(
    micGranted: Boolean,
    modelsReady: Boolean,
    onShowImePicker: () -> Unit,
    onOpenImeSettings: () -> Unit
) {
    val micStatus = if (micGranted) {
        stringResource(R.string.setup_mic_granted)
    } else {
        stringResource(R.string.setup_mic_missing)
    }
    val modelsStatusText = if (modelsReady) {
        stringResource(R.string.calibration_models_ready)
    } else {
        stringResource(R.string.calibration_models_missing)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = stringResource(R.string.calibration_section_title),
            style = MaterialTheme.typography.titleLarge
        )
        Text(
            text = stringResource(R.string.calibration_intro),
            style = MaterialTheme.typography.bodyMedium
        )
        Text(
            text = micStatus,
            style = MaterialTheme.typography.bodyMedium
        )
        Text(
            text = modelsStatusText,
            style = MaterialTheme.typography.bodyMedium
        )
        Text(
            text = stringResource(R.string.calibration_tip_environment),
            style = MaterialTheme.typography.bodyMedium
        )
        Text(
            text = stringResource(R.string.calibration_tip_speech),
            style = MaterialTheme.typography.bodyMedium
        )

        Button(onClick = onShowImePicker) {
            Text(text = stringResource(R.string.calibration_action_open_picker))
        }
        OutlinedButton(onClick = onOpenImeSettings) {
            Text(text = stringResource(R.string.calibration_action_open_settings))
        }
    }
}

@Composable
private fun ModelsScreen(
    liteRtReady: Boolean,
    moonshineReady: Boolean,
    liteRtDownloading: Boolean,
    moonshineDownloading: Boolean,
    liteRtProgress: Int,
    moonshineProgress: Int,
    downloadMessage: String?,
    updatesMessage: String?,
    onDownloadAll: () -> Unit,
    onDownloadLiteRt: () -> Unit,
    onDownloadMoonshine: () -> Unit,
    onCheckUpdates: () -> Unit,
    actionsEnabled: Boolean
) {
    val context = LocalContext.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = stringResource(R.string.models_section_title),
            style = MaterialTheme.typography.titleLarge
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Button(
                onClick = onDownloadAll,
                enabled = actionsEnabled && !(liteRtReady && moonshineReady)
            ) {
                Text(text = stringResource(R.string.setup_download_all))
            }
        }

        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Text(
                    text = stringResource(R.string.models_check_updates_section_title),
                    style = MaterialTheme.typography.titleMedium
                )
                Text(
                    text = stringResource(R.string.models_check_updates_section_description),
                    style = MaterialTheme.typography.bodyMedium
                )
                OutlinedButton(
                    onClick = onCheckUpdates,
                    enabled = actionsEnabled
                ) {
                    Text(text = stringResource(R.string.models_check_updates_action))
                }
                if (!updatesMessage.isNullOrBlank()) {
                    Text(text = updatesMessage, style = MaterialTheme.typography.bodySmall)
                }
            }
        }

        if (!downloadMessage.isNullOrBlank()) {
            Text(text = downloadMessage, style = MaterialTheme.typography.bodySmall)
        }

        Text(
            text = stringResource(
                R.string.setup_model_row,
                stringResource(R.string.setup_model_litert),
                humanReadableSize(context, ModelCatalog.liteRtLm.sizeBytes),
                modelStatus(context, liteRtReady, liteRtDownloading, liteRtProgress)
            ),
            style = MaterialTheme.typography.bodyMedium
        )
        Text(text = ModelCatalog.liteRtLm.notes, style = MaterialTheme.typography.bodySmall)
        Button(
            onClick = onDownloadLiteRt,
            enabled = actionsEnabled && !liteRtReady
        ) {
            Text(text = stringResource(R.string.setup_download_litert))
        }

        Text(
            text = stringResource(
                R.string.setup_model_row,
                stringResource(R.string.setup_model_moonshine),
                humanReadableSize(context, ModelCatalog.moonshineMediumStreamingTotalBytes),
                modelStatus(context, moonshineReady, moonshineDownloading, moonshineProgress)
            ),
            style = MaterialTheme.typography.bodyMedium
        )
        Text(
            text = stringResource(R.string.setup_model_moonshine_note),
            style = MaterialTheme.typography.bodySmall
        )
        Button(
            onClick = onDownloadMoonshine,
            enabled = actionsEnabled && !moonshineReady
        ) {
            Text(text = stringResource(R.string.setup_download_moonshine))
        }
    }
}

@Preview(showBackground = true)
@Composable
private fun VoiceKeyboardSetupRootPreview() {
    VoiceTheme {
        HomeScreen(
            onOpenSetup = {},
            onOpenModels = {},
            onOpenOnboarding = {},
            onOpenCalibration = {},
            onOpenSettings = {}
        )
    }
}

private fun modelStatus(context: Context, ready: Boolean, downloading: Boolean, progress: Int): String {
    return when {
        ready -> context.getString(R.string.setup_status_ready)
        downloading -> context.getString(R.string.setup_status_downloading, progress)
        else -> context.getString(R.string.setup_status_missing)
    }
}

private fun humanReadableSize(context: Context, bytes: Long): String {
    if (bytes <= 0L) return context.getString(R.string.setup_unknown_value)
    val mb = bytes / (1024.0 * 1024.0)
    return String.format(Locale.US, "%.0f MB", mb)
}

private suspend fun downloadSpecAwait(
    downloader: ModelDownloader,
    spec: ModelSpec,
    force: Boolean
): ModelDownloadResult = suspendCancellableCoroutine { cont ->
    downloader.download(
        spec = spec,
        force = force,
        onProgress = { },
        onComplete = { result ->
            if (cont.isActive) cont.resume(result)
        }
    )
}

private fun downloadResultMessage(context: Context, spec: ModelSpec, result: ModelDownloadResult): String? {
    val modelId = spec.id
    return when (result) {
        ModelDownloadResult.Success,
        ModelDownloadResult.AlreadyAvailable -> null

        is ModelDownloadResult.HttpError -> context.getString(
            R.string.setup_download_error_http,
            modelId,
            result.code
        )

        is ModelDownloadResult.HashMismatch -> context.getString(
            R.string.setup_download_error_hash,
            modelId
        )

        is ModelDownloadResult.SizeMismatch -> context.getString(
            R.string.setup_download_error_size,
            modelId
        )

        is ModelDownloadResult.NetworkError -> context.getString(
            R.string.setup_download_error_network,
            modelId
        )

        is ModelDownloadResult.StorageError -> context.getString(
            R.string.setup_download_error_storage,
            modelId
        )

        is ModelDownloadResult.UnknownError -> context.getString(
            R.string.setup_download_error_unknown,
            modelId
        )

        ModelDownloadResult.InvalidSpec -> context.getString(
            R.string.setup_download_error_invalid,
            modelId
        )
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
