package com.sanogueralorenzo.voice.setup

import android.content.Context
import com.airbnb.mvrx.Fail
import com.airbnb.mvrx.Loading
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.Success
import com.airbnb.mvrx.Uninitialized
import com.airbnb.mvrx.withState
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelDownloadResult
import com.sanogueralorenzo.voice.models.ModelDownloader
import com.sanogueralorenzo.voice.models.ModelSpec
import com.sanogueralorenzo.voice.models.ModelUpdateChecker
import com.sanogueralorenzo.voice.settings.VoiceSettingsStore
import com.sanogueralorenzo.voice.summary.PromptTemplateStore
import kotlin.coroutines.resume
import kotlinx.coroutines.Dispatchers
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

class SetupViewModel(
    initialState: SetupUiState,
    context: Context,
    private val settingsStore: VoiceSettingsStore,
    private val updateChecker: ModelUpdateChecker,
    private val setupRepository: SetupRepository
) : MavericksViewModel<SetupUiState>(initialState) {
    private val appContext = context.applicationContext
    private val downloader = ModelDownloader(appContext)

    fun shutdown() {
        downloader.shutdown()
    }

    fun refreshMicPermission() {
        setState { copy(micGranted = setupRepository.hasMicPermission()) }
    }

    fun refreshKeyboardStatus() {
        val keyboardStatus = setupRepository.keyboardStatus()
        setState {
            copy(
                voiceImeEnabled = keyboardStatus.enabled,
                voiceImeSelected = keyboardStatus.selected
            )
        }
    }

    fun onMicPermissionResult(granted: Boolean) {
        setState { copy(micGranted = granted) }
        refreshKeyboardStatus()
    }

    fun setKeyboardTestInput(value: String) {
        setState { copy(keyboardTestInput = value) }
    }

    fun setLiteRtRewriteEnabled(enabled: Boolean) {
        settingsStore.setLiteRtRewriteEnabled(enabled)
        setState { copy(liteRtRewriteEnabled = enabled) }
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
                )

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
                )

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
                    )
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
                setState { copy(moonshineReady = moonshineReady) }
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
                    ).also {
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
                    )
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
        fun runPrompt() {
            val promptReady = withState(this) { state ->
                state.promptReady
            }
            if (promptReady) {
                setState {
                    copy(
                        modelMessage = appContext.getString(R.string.setup_download_all_completed)
                    )
                }
                refreshModelReadiness()
                return
            }
            startPromptDownload(allowWhileAnotherDownloadActive = true) { success ->
                if (!success) return@startPromptDownload
                setState {
                    copy(
                        modelMessage = appContext.getString(R.string.setup_download_all_completed)
                    )
                }
                refreshModelReadiness()
            }
        }

        fun runLiteRt() {
            val liteRtReady = withState(this) { state ->
                state.liteRtReady
            }
            if (liteRtReady) {
                runPrompt()
                return
            }
            startLiteRtDownload(allowWhileAnotherDownloadActive = true) { success ->
                if (!success) return@startLiteRtDownload
                runPrompt()
            }
        }

        fun runMoonshine() {
            val moonshineReady = withState(this) { state ->
                state.moonshineReady
            }
            if (moonshineReady) {
                runLiteRt()
                return
            }
            startMoonshineDownload { success ->
                if (!success) return@startMoonshineDownload
                runLiteRt()
            }
        }

        runMoonshine()
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
                        setState { copy(modelMessage = downloadResultMessage(spec, result)) }
                        onComplete(false)
                        return@download
                    }
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
}
