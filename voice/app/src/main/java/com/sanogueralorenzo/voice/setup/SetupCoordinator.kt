package com.sanogueralorenzo.voice.setup

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelDownloadResult
import com.sanogueralorenzo.voice.models.ModelDownloader
import com.sanogueralorenzo.voice.models.ModelSpec
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.models.ModelUpdateChecker
import com.sanogueralorenzo.voice.settings.VoiceSettingsStore
import kotlin.coroutines.resume
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

class SetupCoordinator(
    context: Context,
    private val scope: CoroutineScope,
    private val settingsStore: VoiceSettingsStore,
    private val updateChecker: ModelUpdateChecker
) {
    private val appContext = context.applicationContext
    private val downloader = ModelDownloader(appContext)

    var uiState by mutableStateOf(
        SetupUiState(
            micGranted = hasMicPermission(),
            liteRtRewriteEnabled = settingsStore.isLiteRtRewriteEnabled(),
            customInstructions = settingsStore.customInstructions()
        )
    )
        private set

    fun shutdown() {
        downloader.shutdown()
    }

    fun refreshMicPermission() {
        uiState = uiState.copy(micGranted = hasMicPermission())
    }

    fun onMicPermissionResult(granted: Boolean) {
        uiState = uiState.copy(micGranted = granted)
    }

    fun setKeyboardTestInput(value: String) {
        uiState = uiState.copy(keyboardTestInput = value)
    }

    fun setLiteRtRewriteEnabled(enabled: Boolean) {
        settingsStore.setLiteRtRewriteEnabled(enabled)
        uiState = uiState.copy(liteRtRewriteEnabled = enabled)
    }

    fun setCustomInstructions(value: String) {
        val normalized = value.take(VoiceSettingsStore.MAX_CUSTOM_INSTRUCTIONS_CHARS)
        settingsStore.setCustomInstructions(normalized)
        uiState = uiState.copy(customInstructions = normalized)
    }

    fun isAnyDownloading(): Boolean {
        return uiState.liteRtDownloading || uiState.moonshineDownloading || uiState.updatesRunning
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
            uiState = uiState.copy(
                liteRtReady = liteRt,
                moonshineReady = moonshine
            )
        }
    }

    fun checkForModelUpdates() {
        if (isAnyDownloading()) return
        uiState = uiState.copy(
            updatesMessage = appContext.getString(R.string.models_check_updates_running),
            updatesRunning = true
        )
        scope.launch {
            try {
                val allSpecs = buildList {
                    add(ModelCatalog.liteRtLm)
                    addAll(ModelCatalog.moonshineMediumStreamingSpecs)
                }
                when (val check = withContext(Dispatchers.IO) { updateChecker.check(allSpecs) }) {
                    is ModelUpdateChecker.CheckResult.UpToDate -> {
                        uiState = uiState.copy(
                            updatesMessage = appContext.getString(R.string.models_check_updates_none)
                        )
                    }

                    is ModelUpdateChecker.CheckResult.Unreachable -> {
                        uiState = uiState.copy(
                            updatesMessage = appContext.getString(R.string.models_check_updates_unreachable)
                        )
                    }

                    is ModelUpdateChecker.CheckResult.UpdatesAvailable -> {
                        uiState = uiState.copy(
                            updatesMessage = appContext.getString(
                                R.string.models_check_updates_downloading,
                                check.updates.size
                            )
                        )
                        var applied = 0
                        var firstFailure: String? = null
                        for (candidate in check.updates) {
                            val result = downloadSpecAwait(
                                spec = candidate.spec,
                                force = true
                            )
                            val ok = result is ModelDownloadResult.Success ||
                                result is ModelDownloadResult.AlreadyAvailable
                            if (ok) {
                                applied += 1
                                withContext(Dispatchers.IO) { updateChecker.markApplied(candidate) }
                            } else if (firstFailure == null) {
                                firstFailure = downloadResultMessage(candidate.spec, result)
                            }
                        }
                        if (!firstFailure.isNullOrBlank()) {
                            uiState = uiState.copy(modelMessage = firstFailure)
                        }
                        val message = if (applied == check.updates.size) {
                            appContext.getString(
                                R.string.models_check_updates_applied,
                                applied
                            )
                        } else {
                            appContext.getString(
                                R.string.models_check_updates_partial,
                                applied,
                                check.updates.size
                            )
                        }
                        uiState = uiState.copy(updatesMessage = message)
                    }
                }
                refreshModelReadiness()
            } finally {
                uiState = uiState.copy(updatesRunning = false)
            }
        }
    }

    fun startLiteRtDownload(onComplete: (Boolean) -> Unit = {}) {
        if (uiState.liteRtReady || isAnyDownloading()) {
            onComplete(uiState.liteRtReady)
            return
        }
        uiState = uiState.copy(
            liteRtDownloading = true,
            liteRtProgress = 0,
            modelMessage = null
        )
        downloader.download(
            spec = ModelCatalog.liteRtLm,
            onProgress = { percent ->
                uiState = uiState.copy(liteRtProgress = percent)
            },
            onComplete = { result ->
                val ready = result is ModelDownloadResult.Success ||
                    result is ModelDownloadResult.AlreadyAvailable
                uiState = uiState.copy(
                    liteRtDownloading = false,
                    liteRtReady = ready,
                    modelMessage = if (ready) {
                        null
                    } else {
                        downloadResultMessage(ModelCatalog.liteRtLm, result)
                    }
                )
                if (!ready) refreshModelReadiness()
                onComplete(ready)
            }
        )
    }

    fun startMoonshineDownload(onComplete: (Boolean) -> Unit = {}) {
        startModelPackDownload(
            specs = ModelCatalog.moonshineMediumStreamingSpecs,
            ready = uiState.moonshineReady,
            setDownloading = { downloading ->
                uiState = uiState.copy(moonshineDownloading = downloading)
            },
            setProgress = { progress ->
                uiState = uiState.copy(moonshineProgress = progress)
            },
            setReady = { ready ->
                uiState = uiState.copy(moonshineReady = ready)
            },
            onComplete = onComplete
        )
    }

    fun downloadAllModels() {
        if (uiState.liteRtReady && uiState.moonshineReady) {
            uiState = uiState.copy(
                modelMessage = appContext.getString(R.string.setup_download_all_already_ready)
            )
            return
        }
        fun runMoonshine() {
            if (uiState.moonshineReady) {
                uiState = uiState.copy(
                    modelMessage = appContext.getString(R.string.setup_download_all_completed)
                )
                refreshModelReadiness()
                return
            }
            startMoonshineDownload { success ->
                if (!success) return@startMoonshineDownload
                uiState = uiState.copy(
                    modelMessage = appContext.getString(R.string.setup_download_all_completed)
                )
                refreshModelReadiness()
            }
        }
        if (uiState.liteRtReady) {
            runMoonshine()
        } else {
            startLiteRtDownload { success ->
                if (!success) return@startLiteRtDownload
                runMoonshine()
            }
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
        uiState = uiState.copy(modelMessage = null)
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
                        uiState = uiState.copy(modelMessage = downloadResultMessage(spec, result))
                        onComplete(false)
                        return@download
                    }
                    runNext(index + 1)
                }
            )
        }

        runNext(0)
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

    private fun hasMicPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            appContext,
            Manifest.permission.RECORD_AUDIO
        ) == PackageManager.PERMISSION_GRANTED
    }
}
