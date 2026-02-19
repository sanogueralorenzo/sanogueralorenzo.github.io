package com.sanogueralorenzo.voice.setup

import android.content.Context
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
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
import com.airbnb.mvrx.Success
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
import com.sanogueralorenzo.voice.summary.PromptTemplateStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class SetupModelsState(
    val connectedToWifi: Boolean = true,
    val allowMobileDataDownloads: Boolean = false,
    val liteRtReady: Boolean = false,
    val moonshineReady: Boolean = false,
    val promptReady: Boolean = false,
    val liteRtDownloading: Boolean = false,
    val moonshineDownloading: Boolean = false,
    val promptDownloading: Boolean = false,
    val liteRtProgress: Int = 0,
    val moonshineProgress: Int = 0,
    val promptProgress: Int = 0,
    val modelMessage: String? = null
) : MavericksState

class SetupModelsViewModel(
    initialState: SetupModelsState,
    context: Context,
    private val setupRepository: SetupRepository
) : MavericksViewModel<SetupModelsState>(initialState) {
    private val appContext = context.applicationContext
    private val downloader = ModelDownloader(appContext)

    init {
        setState {
            copy(connectedToWifi = setupRepository.isConnectedToWifi())
        }
        refreshModelReadiness()
        viewModelScope.launch {
            setupRepository.wifiConnected.collectLatest { connected ->
                setState {
                    copy(
                        connectedToWifi = connected,
                        allowMobileDataDownloads = if (connected) false else allowMobileDataDownloads
                    )
                }
            }
        }
    }

    fun shutdown() {
        downloader.shutdown()
    }

    fun setAllowMobileDataDownloads(allowed: Boolean) {
        setState { copy(allowMobileDataDownloads = allowed) }
    }

    fun refreshModelReadiness() {
        viewModelScope.launch {
            val readiness = withContext(Dispatchers.IO) {
                setupRepository.readModelReadiness()
            }
            setState {
                copy(
                    liteRtReady = readiness.liteRtReady,
                    moonshineReady = readiness.moonshineReady,
                    promptReady = readiness.promptReady,
                    liteRtProgress = if (readiness.liteRtReady) 100 else liteRtProgress,
                    moonshineProgress = if (readiness.moonshineReady) 100 else moonshineProgress,
                    promptProgress = if (readiness.promptReady) 100 else promptProgress
                )
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
        val targets = buildList {
            if (!startingState.moonshineReady) add(DownloadTarget.MOONSHINE)
            if (!startingState.liteRtReady) add(DownloadTarget.LITERT)
            if (!startingState.promptReady) add(DownloadTarget.PROMPT)
        }

        fun runTarget(index: Int) {
            if (index >= targets.size) {
                setState {
                    copy(
                        modelMessage = appContext.getString(R.string.setup_download_all_completed)
                    )
                }
                refreshModelReadiness()
                return
            }
            when (targets[index]) {
                DownloadTarget.MOONSHINE -> {
                    startMoonshineDownload { success ->
                        if (!success) return@startMoonshineDownload
                        runTarget(index + 1)
                    }
                }

                DownloadTarget.LITERT -> {
                    startLiteRtDownload(allowWhileAnotherDownloadActive = true) { success ->
                        if (!success) return@startLiteRtDownload
                        runTarget(index + 1)
                    }
                }

                DownloadTarget.PROMPT -> {
                    startPromptDownload(allowWhileAnotherDownloadActive = true) { success ->
                        if (!success) return@startPromptDownload
                        runTarget(index + 1)
                    }
                }

                DownloadTarget.COMPLETE -> Unit
            }
        }

        runTarget(index = 0)
    }

    private fun startLiteRtDownload(
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
                    )
                }
                if (!ready) refreshModelReadiness()
                onComplete(ready)
            }
        )
    }

    private fun startMoonshineDownload(onComplete: (Boolean) -> Unit = {}) {
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
                setState { copy(moonshineReady = moonshineReady) }
            },
            onComplete = onComplete
        )
    }

    private fun startPromptDownload(
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
        viewModelScope.launch {
            val result = withContext(Dispatchers.IO) {
                setupRepository.ensurePromptDownloaded(force = false)
            }
            val ready = result is PromptTemplateStore.DownloadResult.Success ||
                result is PromptTemplateStore.DownloadResult.AlreadyAvailable
            setState {
                copy(
                    promptDownloading = false,
                    promptReady = ready,
                    promptProgress = if (ready) 100 else 0,
                    modelMessage = if (ready) {
                        null
                    } else {
                        promptDownloadResultMessage(result)
                    }
                )
            }
            onComplete(ready)
        }
    }

    private fun startModelPackDownload(
        specs: List<ModelSpec>,
        ready: Boolean,
        setDownloading: (Boolean) -> Unit,
        setProgress: (Int) -> Unit,
        setReady: (Boolean) -> Unit,
        onComplete: (Boolean) -> Unit = {}
    ) {
        if (ready || withState(this) { state -> isAnyDownloading(state) }) {
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

    private fun isAnyDownloading(state: SetupModelsState): Boolean {
        return state.liteRtDownloading || state.moonshineDownloading || state.promptDownloading
    }

    private enum class DownloadTarget {
        MOONSHINE,
        LITERT,
        PROMPT,
        COMPLETE
    }

    companion object : MavericksViewModelFactory<SetupModelsViewModel, SetupModelsState> {
        override fun create(
            viewModelContext: ViewModelContext,
            state: SetupModelsState
        ): SetupModelsViewModel {
            val app = viewModelContext.app<VoiceApp>()
            return SetupModelsViewModel(
                initialState = state,
                context = app.applicationContext,
                setupRepository = app.appGraph.setupRepository
            )
        }
    }
}

private data class SetupDownloadModelsPresentation(
    val allDownloadsReady: Boolean,
    val downloadInProgress: Boolean,
    val requiresMobileDataApproval: Boolean,
    val canStartDownload: Boolean,
    val shouldShowTotalProgress: Boolean,
    val totalProgressFraction: Float,
    val downloadingTarget: DownloadTarget?
)

private enum class DownloadTarget {
    MOONSHINE,
    LITERT,
    PROMPT
}

@Composable
fun SetupDownloadModelsScreen(
    onModelsReady: () -> Unit
) {
    val lifecycleOwner = LocalLifecycleOwner.current
    val viewModel = mavericksViewModel<SetupModelsViewModel, SetupModelsState>()
    val state by viewModel.collectAsStateWithLifecycle()
    var modelsReadyNotified by rememberSaveable { mutableStateOf(false) }

    DisposableEffect(viewModel) {
        onDispose { viewModel.shutdown() }
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_START || event == Lifecycle.Event.ON_RESUME) {
                viewModel.refreshModelReadiness()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(Unit) {
        viewModel.refreshModelReadiness()
    }

    val allReady = state.liteRtReady && state.moonshineReady && state.promptReady
    val downloading = state.liteRtDownloading || state.moonshineDownloading || state.promptDownloading
    LaunchedEffect(allReady, downloading) {
        if (allReady && !downloading && !modelsReadyNotified) {
            modelsReadyNotified = true
            onModelsReady()
        }
        if (!allReady) {
            modelsReadyNotified = false
        }
    }

    SetupDownloadModelsContent(
        state = state,
        onAllowMobileDataChange = viewModel::setAllowMobileDataDownloads,
        onDownloadModels = viewModel::downloadAllModels
    )
}

@Composable
private fun SetupDownloadModelsContent(
    state: SetupModelsState,
    onAllowMobileDataChange: (Boolean) -> Unit,
    onDownloadModels: () -> Unit
) {
    val presentation = buildSetupDownloadModelsPresentation(state)
    val downloadingModelLabel = when (presentation.downloadingTarget) {
        DownloadTarget.MOONSHINE -> stringResource(R.string.setup_model_moonshine)
        DownloadTarget.LITERT -> stringResource(R.string.setup_model_litert)
        DownloadTarget.PROMPT -> stringResource(R.string.setup_model_prompt)
        null -> null
    }

    SetupStepScaffold(
        title = stringResource(R.string.setup_step_models),
        body = {
            Text(
                text = stringResource(R.string.setup_models_intro),
                style = MaterialTheme.typography.bodyMedium
            )
            Text(
                text = stringResource(R.string.setup_models_intro_bullet_asr),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = stringResource(R.string.setup_models_intro_bullet_it),
                style = MaterialTheme.typography.bodySmall
            )
            if (!state.modelMessage.isNullOrBlank()) {
                Text(
                    text = state.modelMessage,
                    style = MaterialTheme.typography.bodySmall
                )
            }
            if (presentation.shouldShowTotalProgress) {
                if (presentation.downloadInProgress && downloadingModelLabel != null) {
                    Text(
                        text = stringResource(R.string.setup_download_status_model, downloadingModelLabel),
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                LinearProgressIndicator(
                    progress = { presentation.totalProgressFraction },
                    modifier = Modifier.fillMaxWidth()
                )
            }
            if (presentation.allDownloadsReady) {
                Text(
                    text = stringResource(R.string.setup_models_ready),
                    style = MaterialTheme.typography.bodySmall
                )
            }
            if (presentation.requiresMobileDataApproval && !presentation.allDownloadsReady) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Checkbox(
                        checked = state.allowMobileDataDownloads,
                        onCheckedChange = onAllowMobileDataChange
                    )
                    Text(
                        text = stringResource(R.string.setup_allow_mobile_data),
                        style = MaterialTheme.typography.bodySmall
                    )
                }
            }
        },
        actions = {
            if (presentation.requiresMobileDataApproval && !presentation.allDownloadsReady) {
                Text(
                    text = stringResource(R.string.setup_models_mobile_data_warning),
                    style = MaterialTheme.typography.bodySmall
                )
            }
            Button(
                onClick = onDownloadModels,
                enabled = presentation.canStartDownload,
                modifier = Modifier.fillMaxWidth()
            ) {
                Text(text = stringResource(R.string.setup_download_models))
            }
        }
    )
}

private fun buildSetupDownloadModelsPresentation(
    state: SetupModelsState
): SetupDownloadModelsPresentation {
    val modelsReady = state.liteRtReady && state.moonshineReady
    val allDownloadsReady = modelsReady && state.promptReady
    val downloadInProgress = state.liteRtDownloading || state.moonshineDownloading || state.promptDownloading
    val requiresMobileDataApproval = !state.connectedToWifi
    val canStartDownload = !downloadInProgress &&
        !allDownloadsReady &&
        (!requiresMobileDataApproval || state.allowMobileDataDownloads)

    val liteRtRatio = when {
        state.liteRtReady -> 1f
        state.liteRtDownloading -> state.liteRtProgress.coerceIn(0, 100) / 100f
        else -> 0f
    }
    val moonshineRatio = when {
        state.moonshineReady -> 1f
        state.moonshineDownloading -> state.moonshineProgress.coerceIn(0, 100) / 100f
        else -> 0f
    }
    val promptRatio = when {
        state.promptReady -> 1f
        state.promptDownloading -> state.promptProgress.coerceIn(0, 100) / 100f
        else -> 0f
    }

    val totalModelBytes =
        (ModelCatalog.moonshineMediumStreamingTotalBytes + ModelCatalog.liteRtLm.sizeBytes).toDouble()
            .coerceAtLeast(1.0)
    val completedModelBytes = (ModelCatalog.moonshineMediumStreamingTotalBytes.toDouble() * moonshineRatio) +
        (ModelCatalog.liteRtLm.sizeBytes.toDouble() * liteRtRatio)
    val modelProgressFraction = (completedModelBytes / totalModelBytes).toFloat().coerceIn(0f, 1f)
    val totalProgressFraction = ((modelProgressFraction * 0.99f) + (promptRatio * 0.01f)).coerceIn(0f, 1f)
    val shouldShowTotalProgress =
        downloadInProgress || state.liteRtReady || state.moonshineReady || state.promptReady
    val downloadingTarget = when {
        state.moonshineDownloading -> DownloadTarget.MOONSHINE
        state.liteRtDownloading -> DownloadTarget.LITERT
        state.promptDownloading -> DownloadTarget.PROMPT
        else -> null
    }

    return SetupDownloadModelsPresentation(
        allDownloadsReady = allDownloadsReady,
        downloadInProgress = downloadInProgress,
        requiresMobileDataApproval = requiresMobileDataApproval,
        canStartDownload = canStartDownload,
        shouldShowTotalProgress = shouldShowTotalProgress,
        totalProgressFraction = totalProgressFraction,
        downloadingTarget = downloadingTarget
    )
}
