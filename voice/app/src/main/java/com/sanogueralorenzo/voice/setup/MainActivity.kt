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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
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
import com.sanogueralorenzo.voice.asr.MoonshineAsrProfile
import com.sanogueralorenzo.voice.asr.MoonshineAsrProfileStore
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelDownloadResult
import com.sanogueralorenzo.voice.models.ModelDownloader
import com.sanogueralorenzo.voice.models.ModelSpec
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.ui.theme.VoiceTheme
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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
    const val PROFILE = "profile"
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
    val moonshineProfileStore = remember(appContext) { MoonshineAsrProfileStore(appContext) }
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
    var modelMessage by remember { mutableStateOf<String?>(null) }
    var moonshineProfile by remember { mutableStateOf(moonshineProfileStore.get()) }

    val lifecycleOwner = LocalLifecycleOwner.current

    fun isAnyDownloading(): Boolean {
        return liteRtDownloading || moonshineDownloading
    }

    fun refreshModelReadiness() {
        scope.launch {
            val liteRt = withContext(Dispatchers.IO) {
                ModelStore.isModelReadyStrict(appContext, ModelCatalog.liteRtLm)
            }
            val moonshine = withContext(Dispatchers.IO) {
                ModelCatalog.moonshineTinyStreamingSpecs.all {
                    ModelStore.isModelReadyStrict(appContext, it)
                }
            }
            liteRtReady = liteRt
            moonshineReady = moonshine
            moonshineProfile = moonshineProfileStore.get()
        }
    }

    fun checkForModelUpdates() {
        if (isAnyDownloading()) return
        modelMessage = context.getString(R.string.models_check_updates_running)
        scope.launch {
            val liteRt = withContext(Dispatchers.IO) {
                ModelStore.isModelReadyStrict(appContext, ModelCatalog.liteRtLm)
            }
            val moonshine = withContext(Dispatchers.IO) {
                ModelCatalog.moonshineTinyStreamingSpecs.all {
                    ModelStore.isModelReadyStrict(appContext, it)
                }
            }
            liteRtReady = liteRt
            moonshineReady = moonshine
            modelMessage = if (liteRt && moonshine) {
                context.getString(R.string.models_check_updates_none)
            } else {
                context.getString(R.string.models_check_updates_found)
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

    fun startMoonshineDownload(onComplete: (Boolean) -> Unit = {}) {
        if (moonshineReady || isAnyDownloading()) {
            onComplete(moonshineReady)
            return
        }
        val specs = ModelCatalog.moonshineTinyStreamingSpecs
        if (specs.isEmpty()) {
            onComplete(false)
            return
        }

        moonshineDownloading = true
        moonshineProgress = 0
        modelMessage = null
        val total = specs.size

        fun runNext(index: Int) {
            if (index >= total) {
                moonshineDownloading = false
                moonshineProgress = 100
                moonshineReady = true
                onComplete(true)
                return
            }
            val spec = specs[index]
            downloader.download(
                spec = spec,
                onProgress = { percent ->
                    val overall = ((index * 100f) + percent.toFloat()) / total.toFloat()
                    moonshineProgress = overall.toInt().coerceIn(0, 100)
                },
                onComplete = { result ->
                    val success = result is ModelDownloadResult.Success ||
                        result is ModelDownloadResult.AlreadyAvailable
                    if (!success) {
                        moonshineDownloading = false
                        moonshineReady = false
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

    fun setMoonshineProfile(profile: MoonshineAsrProfile) {
        moonshineProfileStore.set(profile)
        moonshineProfile = profile
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
    val canGoBack = backStackEntry?.destination?.route != MainRoute.HOME

    Scaffold(
        topBar = {
            CenterAlignedTopAppBar(
                title = {
                    Text(
                        text = stringResource(R.string.main_title_voice_keyboard),
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
                }
            )
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
                    onOpenProfile = { navController.navigate(MainRoute.PROFILE) }
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
                    message = modelMessage,
                    onDownloadAll = { downloadAllModels() },
                    onDownloadLiteRt = { startLiteRtDownload() },
                    onDownloadMoonshine = { startMoonshineDownload() },
                    onCheckUpdates = { checkForModelUpdates() },
                    actionsEnabled = !isAnyDownloading()
                )
            }

            composable(MainRoute.PROFILE) {
                ProfileScreen(
                    selected = moonshineProfile,
                    onSelect = { setMoonshineProfile(it) },
                    enabled = !isAnyDownloading()
                )
            }
        }
    }
}

@Composable
private fun HomeScreen(
    onOpenSetup: () -> Unit,
    onOpenModels: () -> Unit,
    onOpenProfile: () -> Unit
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
            title = stringResource(R.string.home_section_profile_title),
            description = stringResource(R.string.home_section_profile_description),
            onClick = onOpenProfile
        )
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
private fun ModelsScreen(
    liteRtReady: Boolean,
    moonshineReady: Boolean,
    liteRtDownloading: Boolean,
    moonshineDownloading: Boolean,
    liteRtProgress: Int,
    moonshineProgress: Int,
    message: String?,
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
            OutlinedButton(
                onClick = onCheckUpdates,
                enabled = actionsEnabled
            ) {
                Text(text = stringResource(R.string.models_check_updates_action))
            }
        }

        if (!message.isNullOrBlank()) {
            Text(text = message, style = MaterialTheme.typography.bodySmall)
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
                humanReadableSize(context, ModelCatalog.moonshineTinyStreamingTotalBytes),
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

@Composable
private fun ProfileScreen(
    selected: MoonshineAsrProfile,
    onSelect: (MoonshineAsrProfile) -> Unit,
    enabled: Boolean
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = stringResource(R.string.setup_asr_profile_title),
            style = MaterialTheme.typography.titleLarge
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            MoonshineAsrProfile.entries.forEach { profile ->
                val isSelected = profile == selected
                if (isSelected) {
                    Button(
                        onClick = { onSelect(profile) },
                        enabled = enabled
                    ) {
                        Text(text = profile.displayName)
                    }
                } else {
                    OutlinedButton(
                        onClick = { onSelect(profile) },
                        enabled = enabled
                    ) {
                        Text(text = profile.displayName)
                    }
                }
            }
        }

        Text(
            text = stringResource(
                R.string.setup_asr_profile_note,
                selected.displayName
            ),
            style = MaterialTheme.typography.bodySmall
        )
    }
}

@Preview(showBackground = true)
@Composable
private fun VoiceKeyboardSetupRootPreview() {
    VoiceTheme {
        HomeScreen(
            onOpenSetup = {},
            onOpenModels = {},
            onOpenProfile = {}
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
