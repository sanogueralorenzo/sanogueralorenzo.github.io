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
import androidx.lifecycle.viewModelScope
import com.airbnb.mvrx.Async
import com.airbnb.mvrx.Fail
import com.airbnb.mvrx.Loading
import com.airbnb.mvrx.MavericksState
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.Success
import com.airbnb.mvrx.Uninitialized
import com.airbnb.mvrx.ViewModelContext
import com.airbnb.mvrx.compose.collectAsStateWithLifecycle
import com.airbnb.mvrx.compose.mavericksViewModel
import com.airbnb.mvrx.withState
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.VoiceApp
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelDownloadResult
import com.sanogueralorenzo.voice.models.ModelDownloader
import com.sanogueralorenzo.voice.models.ModelSpec
import com.sanogueralorenzo.voice.models.ModelUpdateChecker
import com.sanogueralorenzo.voice.summary.PromptTemplateStore
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

data class ModelReadiness(
    val liteRtReady: Boolean,
    val moonshineReady: Boolean,
    val promptReady: Boolean,
    val promptVersion: String?
)

data class ModelUpdatesOutcome(
    val updatesMessage: String,
    val modelMessage: String?,
    val liteRtReady: Boolean,
    val moonshineReady: Boolean,
    val promptReady: Boolean,
    val promptVersion: String?
)

data class SetupUiState(
    val micGranted: Boolean = false,
    val voiceImeEnabled: Boolean = false,
    val voiceImeSelected: Boolean = false,
    val wifiConnected: Boolean = true,
    val introDismissed: Boolean = false,
    val requiredStep: SetupRepository.RequiredStep = SetupRepository.RequiredStep.INTRO,
    val liteRtReady: Boolean = false,
    val moonshineReady: Boolean = false,
    val promptReady: Boolean = false,
    val liteRtProgress: Int = 0,
    val moonshineProgress: Int = 0,
    val promptProgress: Int = 0,
    val liteRtDownloading: Boolean = false,
    val moonshineDownloading: Boolean = false,
    val promptDownloading: Boolean = false,
    val promptVersion: String? = null,
    val setupSelectKeyboardDone: Boolean = false,
    val updatesRunning: Boolean = false,
    val modelMessage: String? = null,
    val updatesMessage: String? = null,
    val settingsKeyboardTestInput: String = "",
    val themeKeyboardTestInput: String = "",
    val modelReadinessAsync: Async<ModelReadiness> = Uninitialized,
    val updatesAsync: Async<ModelUpdatesOutcome> = Uninitialized
) : MavericksState

class SetupViewModel(
    initialState: SetupUiState,
    context: Context,
    private val updateChecker: ModelUpdateChecker,
    private val setupRepository: SetupRepository
) : MavericksViewModel<SetupUiState>(initialState) {
    private val appContext = context.applicationContext
    private val downloader = ModelDownloader(appContext)

    init {
        setState {
            copy(wifiConnected = setupRepository.isConnectedToWifi()).withDerivedState()
        }
        viewModelScope.launch {
            setupRepository.wifiConnected.collectLatest { connected ->
                setState {
                    copy(wifiConnected = connected)
                }
            }
        }
    }

    fun shutdown() {
        downloader.shutdown()
    }

    fun refreshMicPermission() {
        setState { copy(micGranted = setupRepository.hasMicPermission()).withDerivedState() }
    }

    fun refreshKeyboardStatus() {
        val keyboardStatus = setupRepository.keyboardStatus()
        setState {
            copy(
                voiceImeEnabled = keyboardStatus.enabled,
                voiceImeSelected = keyboardStatus.selected
            ).withDerivedState()
        }
    }

    fun onMicPermissionResult(granted: Boolean) {
        setState { copy(micGranted = granted).withDerivedState() }
        refreshKeyboardStatus()
    }

    fun onSetupIntroContinue() {
        setState { copy(introDismissed = true).withDerivedState() }
    }

    fun refreshSetupSelectKeyboardDone() {
        suspend {
            withContext(Dispatchers.IO) {
                setupRepository.isSetupSelectKeyboardStepDone()
            }
        }.execute { async ->
            when (async) {
                is Success -> copy(setupSelectKeyboardDone = async()).withDerivedState()
                else -> copy()
            }
        }
    }

    fun onSetupSelectKeyboardDone() {
        setState { copy(setupSelectKeyboardDone = true).withDerivedState() }
        viewModelScope.launch {
            setupRepository.setSetupSelectKeyboardStepDone(done = true)
        }
    }

    fun setSettingsKeyboardTestInput(value: String) {
        setState { copy(settingsKeyboardTestInput = value) }
    }

    fun setThemeKeyboardTestInput(value: String) {
        setState { copy(themeKeyboardTestInput = value) }
    }

    fun isAnyDownloading(): Boolean {
        return withState(this) { state ->
            isAnyDownloading(state)
        }
    }

    fun refreshModelReadiness() {
        suspend {
            withContext(Dispatchers.IO) {
                setupRepository.readModelReadiness()
            }
        }.execute { async ->
            when (async) {
                is Success -> copy(
                    modelReadinessAsync = async,
                    liteRtReady = async().liteRtReady,
                    moonshineReady = async().moonshineReady,
                    promptReady = async().promptReady,
                    promptVersion = async().promptVersion
                ).withDerivedState()

                else -> copy(modelReadinessAsync = async)
            }
        }
    }

    fun checkForModelUpdates() {
        val anyDownloading = withState(this) { state ->
            isAnyDownloading(state)
        }
        if (anyDownloading) return
        setState {
            copy(
                updatesMessage = appContext.getString(R.string.models_check_updates_running),
                updatesRunning = true
            )
        }
        suspend {
            val allSpecs = buildList {
                add(ModelCatalog.liteRtLm)
                addAll(ModelCatalog.moonshineMediumStreamingSpecs)
            }
            val check = withContext(Dispatchers.IO) { updateChecker.check(allSpecs) }
            when (check) {
                is ModelUpdateChecker.CheckResult.UpToDate -> {
                    setState {
                        copy(
                            updatesMessage = appContext.getString(
                                R.string.models_check_updates_downloading,
                                1
                            )
                        )
                    }
                    val promptResult = withContext(Dispatchers.IO) {
                        setupRepository.ensurePromptDownloaded(force = true)
                    }
                    val promptSuccess = promptResult is PromptTemplateStore.DownloadResult.Success ||
                        promptResult is PromptTemplateStore.DownloadResult.AlreadyAvailable
                    val promptMessage = if (promptSuccess) {
                        null
                    } else {
                        promptDownloadResultMessage(promptResult)
                    }
                    val updatesMessage = if (promptSuccess) {
                        appContext.getString(R.string.models_check_updates_applied, 1)
                    } else {
                        appContext.getString(R.string.models_check_updates_partial, 0, 1)
                    }
                    buildModelUpdatesOutcome(
                        updatesMessage = updatesMessage,
                        modelMessage = promptMessage
                    )
                }

                is ModelUpdateChecker.CheckResult.Unreachable -> {
                    setState {
                        copy(
                            updatesMessage = appContext.getString(
                                R.string.models_check_updates_downloading,
                                1
                            )
                        )
                    }
                    val promptResult = withContext(Dispatchers.IO) {
                        setupRepository.ensurePromptDownloaded(force = true)
                    }
                    val promptSuccess = promptResult is PromptTemplateStore.DownloadResult.Success ||
                        promptResult is PromptTemplateStore.DownloadResult.AlreadyAvailable
                    val promptMessage = if (promptSuccess) {
                        null
                    } else {
                        promptDownloadResultMessage(promptResult)
                    }
                    val updatesMessage = if (promptSuccess) {
                        appContext.getString(R.string.models_check_updates_applied, 1)
                    } else {
                        appContext.getString(R.string.models_check_updates_unreachable)
                    }
                    buildModelUpdatesOutcome(
                        updatesMessage = updatesMessage,
                        modelMessage = promptMessage
                    )
                }

                is ModelUpdateChecker.CheckResult.UpdatesAvailable -> {
                    val totalUpdates = check.updates.size + 1
                    setState {
                        copy(
                            updatesMessage = appContext.getString(
                                R.string.models_check_updates_downloading,
                                totalUpdates
                            )
                        )
                    }
                    var applied = 0
                    var firstFailure: String? = null
                    for (candidate in check.updates) {
                        val result = downloadSpecAwait(
                            spec = candidate.spec,
                            force = true
                        )
                        val successful = result is ModelDownloadResult.Success ||
                            result is ModelDownloadResult.AlreadyAvailable
                        if (successful) {
                            applied += 1
                            withContext(Dispatchers.IO) { updateChecker.markApplied(candidate) }
                        } else if (firstFailure == null) {
                            firstFailure = downloadResultMessage(candidate.spec, result)
                        }
                    }
                    val promptResult = withContext(Dispatchers.IO) {
                        setupRepository.ensurePromptDownloaded(force = true)
                    }
                    val promptSuccess = promptResult is PromptTemplateStore.DownloadResult.Success ||
                        promptResult is PromptTemplateStore.DownloadResult.AlreadyAvailable
                    if (promptSuccess) {
                        applied += 1
                    } else if (firstFailure == null) {
                        firstFailure = promptDownloadResultMessage(promptResult)
                    }
                    val message = if (applied == totalUpdates) {
                        appContext.getString(
                            R.string.models_check_updates_applied,
                            applied
                        )
                    } else {
                        appContext.getString(
                            R.string.models_check_updates_partial,
                            applied,
                            totalUpdates
                        )
                    }
                    buildModelUpdatesOutcome(
                        updatesMessage = message,
                        modelMessage = firstFailure
                    )
                }
            }
        }.execute { async ->
            when (async) {
                is Loading -> copy(
                    updatesAsync = async,
                    updatesRunning = true
                )

                is Success -> copy(
                    updatesAsync = async,
                    updatesRunning = false,
                    updatesMessage = async().updatesMessage,
                    modelMessage = async().modelMessage ?: modelMessage,
                    liteRtReady = async().liteRtReady,
                    moonshineReady = async().moonshineReady,
                    promptReady = async().promptReady,
                    promptVersion = async().promptVersion
                ).withDerivedState()

                is Fail -> copy(
                    updatesAsync = async,
                    updatesRunning = false,
                    updatesMessage = appContext.getString(R.string.models_check_updates_unreachable)
                )

                is Uninitialized -> copy(updatesAsync = async)
            }
        }
    }

    fun startLiteRtDownload(
        allowWhileAnotherDownloadActive: Boolean = false,
        onComplete: (Boolean) -> Unit = {}
    ) {
        val snapshot = withState(this) { it }
        if (snapshot.liteRtReady || (!allowWhileAnotherDownloadActive && isAnyDownloading(snapshot))) {
            onComplete(snapshot.liteRtReady)
            return
        }
        setState {
            copy(
                liteRtDownloading = true,
                liteRtProgress = 0,
                modelMessage = null
            )
        }
        downloader.download(
            spec = ModelCatalog.liteRtLm,
            onProgress = { percent ->
                setState { copy(liteRtProgress = percent) }
            },
            onComplete = { result ->
                val ready = result is ModelDownloadResult.Success ||
                    result is ModelDownloadResult.AlreadyAvailable
                setState {
                    copy(
                        liteRtDownloading = false,
                        liteRtReady = ready,
                        modelMessage = if (ready) {
                            null
                        } else {
                            downloadResultMessage(ModelCatalog.liteRtLm, result)
                        }
                    ).withDerivedState()
                }
                if (!ready) refreshModelReadiness()
                onComplete(ready)
            }
        )
    }

    fun startMoonshineDownload(onComplete: (Boolean) -> Unit = {}) {
        val ready = withState(this) { state ->
            state.moonshineReady
        }
        startModelPackDownload(
            specs = ModelCatalog.moonshineMediumStreamingSpecs,
            ready = ready,
            setDownloading = { downloading ->
                setState { copy(moonshineDownloading = downloading) }
            },
            setProgress = { progress ->
                setState { copy(moonshineProgress = progress) }
            },
            setReady = { moonshineReady ->
                setState { copy(moonshineReady = moonshineReady).withDerivedState() }
            },
            onComplete = onComplete
        )
    }

    fun startPromptDownload(
        allowWhileAnotherDownloadActive: Boolean = false,
        onComplete: (Boolean) -> Unit = {}
    ) {
        val snapshot = withState(this) { it }
        if (snapshot.promptReady || (!allowWhileAnotherDownloadActive && isAnyDownloading(snapshot))) {
            onComplete(snapshot.promptReady)
            return
        }
        setState {
            copy(
                promptDownloading = true,
                promptProgress = 0,
                modelMessage = null
            )
        }
        suspend {
            withContext(Dispatchers.IO) {
                setupRepository.ensurePromptDownloaded(force = false)
            }
        }.execute { async ->
            when (async) {
                is Loading -> copy(promptDownloading = true)
                is Success -> {
                    val result = async()
                    val ready = result is PromptTemplateStore.DownloadResult.Success ||
                        result is PromptTemplateStore.DownloadResult.AlreadyAvailable
                    copy(
                        promptDownloading = false,
                        promptReady = ready,
                        promptProgress = if (ready) 100 else 0,
                        promptVersion = setupRepository.currentPromptVersion(),
                        modelMessage = if (ready) {
                            null
                        } else {
                            promptDownloadResultMessage(result)
                        }
                    ).withDerivedState().also {
                        onComplete(ready)
                    }
                }

                is Fail -> {
                    onComplete(false)
                    copy(
                        promptDownloading = false,
                        promptReady = false,
                        promptProgress = 0,
                        modelMessage = appContext.getString(R.string.setup_prompt_download_error_unknown)
                    ).withDerivedState()
                }

                is Uninitialized -> copy()
            }
        }
    }

    fun downloadAllModels() {
        val startingState = withState(this) { state -> state }
        if (startingState.liteRtReady && startingState.moonshineReady && startingState.promptReady) {
            setState {
                copy(
                    modelMessage = appContext.getString(R.string.setup_download_all_already_ready)
                )
            }
            return
        }
        fun runFromFirstMissing() {
            val next = withState(this) { state ->
                when {
                    !state.moonshineReady -> DownloadTarget.MOONSHINE
                    !state.liteRtReady -> DownloadTarget.LITERT
                    !state.promptReady -> DownloadTarget.PROMPT
                    else -> DownloadTarget.COMPLETE
                }
            }
            when (next) {
                DownloadTarget.MOONSHINE -> {
                    startMoonshineDownload { success ->
                        if (!success) return@startMoonshineDownload
                        runFromFirstMissing()
                    }
                }

                DownloadTarget.LITERT -> {
                    startLiteRtDownload(allowWhileAnotherDownloadActive = true) { success ->
                        if (!success) return@startLiteRtDownload
                        runFromFirstMissing()
                    }
                }

                DownloadTarget.PROMPT -> {
                    startPromptDownload(allowWhileAnotherDownloadActive = true) { success ->
                        if (!success) return@startPromptDownload
                        runFromFirstMissing()
                    }
                }

                DownloadTarget.COMPLETE -> {
                    setState {
                        copy(
                            modelMessage = appContext.getString(R.string.setup_download_all_completed)
                        )
                    }
                    refreshModelReadiness()
                }
            }
        }

        runFromFirstMissing()
    }

    private fun startModelPackDownload(
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
        setState { copy(modelMessage = null) }
        val total = specs.size
        val byteWeights = specs.map { it.sizeBytes.coerceAtLeast(0L) }
        val totalBytes = byteWeights.sum()
        val useByteWeightedProgress = totalBytes > 0L && byteWeights.all { it > 0L }

        fun overallProgress(index: Int, percent: Int): Int {
            val safePercent = percent.coerceIn(0, 100)
            if (!useByteWeightedProgress) {
                val overall = ((index * 100f) + safePercent.toFloat()) / total.toFloat()
                return overall.toInt().coerceIn(0, 100)
            }
            val completedBytes = byteWeights.take(index).sum()
            val currentBytes = byteWeights.getOrNull(index) ?: 0L
            val currentBytesDownloaded = currentBytes.toDouble() * (safePercent.toDouble() / 100.0)
            val downloadedBytes = completedBytes.toDouble() + currentBytesDownloaded
            return ((downloadedBytes / totalBytes.toDouble()) * 100.0).toInt().coerceIn(0, 100)
        }

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
                    setProgress(overallProgress(index, percent))
                },
                onComplete = { result ->
                    val success = result is ModelDownloadResult.Success ||
                        result is ModelDownloadResult.AlreadyAvailable
                    if (!success) {
                        setDownloading(false)
                        setReady(false)
                        setState { copy(modelMessage = downloadResultMessage(spec, result)) }
                        onComplete(false)
                        return@download
                    }
                    setProgress(overallProgress(index, 100))
                    runNext(index + 1)
                }
            )
        }

        runNext(0)
    }

    private suspend fun buildModelUpdatesOutcome(
        updatesMessage: String,
        modelMessage: String?
    ): ModelUpdatesOutcome {
        val readiness = loadModelReadiness()
        return ModelUpdatesOutcome(
            updatesMessage = updatesMessage,
            modelMessage = modelMessage,
            liteRtReady = readiness.liteRtReady,
            moonshineReady = readiness.moonshineReady,
            promptReady = readiness.promptReady,
            promptVersion = readiness.promptVersion
        )
    }

    private suspend fun loadModelReadiness(): ModelReadiness {
        return withContext(Dispatchers.IO) {
            setupRepository.readModelReadiness()
        }
    }

    private suspend fun downloadSpecAwait(
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

    private fun downloadResultMessage(spec: ModelSpec, result: ModelDownloadResult): String? {
        val modelId = spec.id
        return when (result) {
            ModelDownloadResult.Success,
            ModelDownloadResult.AlreadyAvailable -> null

            is ModelDownloadResult.HttpError -> appContext.getString(
                R.string.setup_download_error_http,
                modelId,
                result.code
            )

            is ModelDownloadResult.HashMismatch -> appContext.getString(
                R.string.setup_download_error_hash,
                modelId
            )

            is ModelDownloadResult.SizeMismatch -> appContext.getString(
                R.string.setup_download_error_size,
                modelId
            )

            is ModelDownloadResult.NetworkError -> appContext.getString(
                R.string.setup_download_error_network,
                modelId
            )

            is ModelDownloadResult.StorageError -> appContext.getString(
                R.string.setup_download_error_storage,
                modelId
            )

            is ModelDownloadResult.UnknownError -> appContext.getString(
                R.string.setup_download_error_unknown,
                modelId
            )

            ModelDownloadResult.InvalidSpec -> appContext.getString(
                R.string.setup_download_error_invalid,
                modelId
            )
        }
    }

    private fun promptDownloadResultMessage(result: PromptTemplateStore.DownloadResult): String? {
        return when (result) {
            is PromptTemplateStore.DownloadResult.Success,
            is PromptTemplateStore.DownloadResult.AlreadyAvailable -> null
            is PromptTemplateStore.DownloadResult.HttpError -> appContext.getString(
                R.string.setup_prompt_download_error_http,
                result.code
            )

            is PromptTemplateStore.DownloadResult.NetworkError -> appContext.getString(
                R.string.setup_prompt_download_error_network
            )

            is PromptTemplateStore.DownloadResult.InvalidPayload -> appContext.getString(
                R.string.setup_prompt_download_error_invalid
            )

            is PromptTemplateStore.DownloadResult.StorageError -> appContext.getString(
                R.string.setup_prompt_download_error_storage
            )

            is PromptTemplateStore.DownloadResult.UnknownError -> appContext.getString(
                R.string.setup_prompt_download_error_unknown
            )
        }
    }

    private fun isAnyDownloading(state: SetupUiState): Boolean {
        return state.liteRtDownloading || state.moonshineDownloading || state.promptDownloading || state.updatesRunning
    }

    private enum class DownloadTarget {
        MOONSHINE,
        LITERT,
        PROMPT,
        COMPLETE
    }

    private fun SetupUiState.withDerivedState(): SetupUiState {
        return copy(requiredStep = computeRequiredStep(this))
    }

    private fun computeRequiredStep(state: SetupUiState): SetupRepository.RequiredStep {
        return SetupRepository.requiredStepForMissing(
            missing = SetupRepository.MissingSetupItems(
                micPermission = !state.micGranted,
                imeEnabled = !state.voiceImeEnabled,
                liteRtModel = !state.liteRtReady,
                moonshineModel = !state.moonshineReady,
                promptTemplate = !state.promptReady
            ),
            introDismissed = state.introDismissed,
            setupSelectKeyboardDone = state.setupSelectKeyboardDone
        )
    }

    companion object : MavericksViewModelFactory<SetupViewModel, SetupUiState> {
        override fun create(
            viewModelContext: ViewModelContext,
            state: SetupUiState
        ): SetupViewModel {
            val app = viewModelContext.app<VoiceApp>()
            return SetupViewModel(
                initialState = state,
                context = app.applicationContext,
                updateChecker = app.appGraph.modelUpdateChecker,
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
    val setupViewModel = mavericksViewModel<SetupViewModel, SetupUiState>()
    val state by setupViewModel.collectAsStateWithLifecycle()
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
                setupViewModel.refreshSetupSelectKeyboardDone()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(Unit) {
        setupViewModel.refreshMicPermission()
        setupViewModel.refreshKeyboardStatus()
        setupViewModel.refreshModelReadiness()
        setupViewModel.refreshSetupSelectKeyboardDone()
    }

    LaunchedEffect(state.wifiConnected) {
        if (state.wifiConnected) allowMobileDataDownloads = false
    }

    val setupTargetRoute = when (state.requiredStep) {
        SetupRepository.RequiredStep.INTRO -> SetupRoute.SETUP_INTRO
        SetupRepository.RequiredStep.MIC_PERMISSION -> SetupRoute.SETUP_MIC
        SetupRepository.RequiredStep.ENABLE_KEYBOARD -> SetupRoute.SETUP_ENABLE_KEYBOARD
        SetupRepository.RequiredStep.DOWNLOAD_MODELS -> SetupRoute.SETUP_MODELS
        SetupRepository.RequiredStep.SELECT_KEYBOARD -> SetupRoute.SETUP_SELECT_KEYBOARD
        SetupRepository.RequiredStep.COMPLETE -> null
    }
    val requiredSetupRoute = if (setupTargetRoute != null && !setupSplashCompleted) {
        SetupRoute.SETUP_SPLASH
    } else {
        setupTargetRoute
    }

    LaunchedEffect(state.requiredStep) {
        if (state.requiredStep == SetupRepository.RequiredStep.COMPLETE) {
            onSetupComplete()
        }
    }

    if (requiredSetupRoute == null) {
        Box(modifier = Modifier.fillMaxSize())
        return
    }

    SetupStepNavHost(
        requiredRoute = requiredSetupRoute,
        connectedToWifi = state.wifiConnected,
        allowMobileDataDownloads = allowMobileDataDownloads,
        uiState = state,
        onAllowMobileDataChange = { allowMobileDataDownloads = it },
        onGrantMic = { permissionLauncher.launch(Manifest.permission.RECORD_AUDIO) },
        onOpenImeSettings = { openImeSettings(context) },
        onDownloadModels = { setupViewModel.downloadAllModels() },
        onSplashFinished = { setupSplashCompleted = true },
        onIntroContinue = { setupViewModel.onSetupIntroContinue() },
        onSetupSelectKeyboardDone = { setupViewModel.onSetupSelectKeyboardDone() }
    )
}

private fun openImeSettings(context: Context) {
    val intent = Intent(Settings.ACTION_INPUT_METHOD_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    context.startActivity(intent)
}
