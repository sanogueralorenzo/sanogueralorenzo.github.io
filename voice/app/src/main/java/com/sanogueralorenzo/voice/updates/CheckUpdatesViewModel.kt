package com.sanogueralorenzo.voice.updates

import android.content.Context
import androidx.lifecycle.viewModelScope
import com.airbnb.mvrx.MavericksViewModelFactory
import com.airbnb.mvrx.MavericksViewModel
import com.airbnb.mvrx.ViewModelContext
import com.sanogueralorenzo.voice.VoiceApp
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelDownloadResult
import com.sanogueralorenzo.voice.models.ModelDownloader
import com.sanogueralorenzo.voice.models.ModelSpec
import com.sanogueralorenzo.voice.models.ModelUpdateChecker
import com.sanogueralorenzo.voice.summary.PromptTemplateStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

private data class CheckUpdatesOutcome(
    val updatesMessage: String,
    val modelMessage: String?
)

class CheckUpdatesViewModel(
    initialState: CheckUpdatesState,
    context: Context,
    private val updateChecker: ModelUpdateChecker
) : MavericksViewModel<CheckUpdatesState>(initialState) {

    private val appContext = context.applicationContext
    private val downloader = ModelDownloader(appContext)
    private val promptTemplateStore = PromptTemplateStore(appContext)

    fun checkForUpdates() {
        var running = false
        withState { state -> running = state.updatesRunning }
        if (running) return
        setState {
            copy(
                updatesRunning = true,
                updatesMessage = appContext.getString(R.string.models_check_updates_running),
                modelMessage = null
            )
        }
        viewModelScope.launch {
            val outcome = runCatching { runUpdateFlow() }
                .getOrElse {
                    CheckUpdatesOutcome(
                        updatesMessage = appContext.getString(R.string.models_check_updates_unreachable),
                        modelMessage = null
                    )
                }
            setState {
                copy(
                    updatesRunning = false,
                    updatesMessage = outcome.updatesMessage,
                    modelMessage = outcome.modelMessage
                )
            }
        }
    }

    fun shutdown() {
        downloader.shutdown()
    }

    private suspend fun runUpdateFlow(): CheckUpdatesOutcome {
        val allSpecs = buildList {
            add(ModelCatalog.liteRtLm)
            addAll(ModelCatalog.moonshineMediumStreamingSpecs)
        }
        val check = withContext(Dispatchers.IO) { updateChecker.check(allSpecs) }
        return when (check) {
            is ModelUpdateChecker.CheckResult.UpToDate -> {
                setDownloadingMessage(totalUpdates = 1)
                val promptResult = withContext(Dispatchers.IO) {
                    promptTemplateStore.ensurePromptDownloaded(force = true)
                }
                val promptSuccess = promptResult is PromptTemplateStore.DownloadResult.Success ||
                    promptResult is PromptTemplateStore.DownloadResult.AlreadyAvailable
                val promptMessage = if (promptSuccess) null else promptDownloadResultMessage(promptResult)
                val updatesMessage = if (promptSuccess) {
                    appContext.getString(R.string.models_check_updates_applied, 1)
                } else {
                    appContext.getString(R.string.models_check_updates_partial, 0, 1)
                }
                CheckUpdatesOutcome(
                    updatesMessage = updatesMessage,
                    modelMessage = promptMessage
                )
            }

            is ModelUpdateChecker.CheckResult.Unreachable -> {
                setDownloadingMessage(totalUpdates = 1)
                val promptResult = withContext(Dispatchers.IO) {
                    promptTemplateStore.ensurePromptDownloaded(force = true)
                }
                val promptSuccess = promptResult is PromptTemplateStore.DownloadResult.Success ||
                    promptResult is PromptTemplateStore.DownloadResult.AlreadyAvailable
                val promptMessage = if (promptSuccess) null else promptDownloadResultMessage(promptResult)
                val updatesMessage = if (promptSuccess) {
                    appContext.getString(R.string.models_check_updates_applied, 1)
                } else {
                    appContext.getString(R.string.models_check_updates_unreachable)
                }
                CheckUpdatesOutcome(
                    updatesMessage = updatesMessage,
                    modelMessage = promptMessage
                )
            }

            is ModelUpdateChecker.CheckResult.UpdatesAvailable -> {
                val totalUpdates = check.updates.size + 1
                setDownloadingMessage(totalUpdates = totalUpdates)
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
                    promptTemplateStore.ensurePromptDownloaded(force = true)
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
                CheckUpdatesOutcome(
                    updatesMessage = message,
                    modelMessage = firstFailure
                )
            }
        }
    }

    private fun setDownloadingMessage(totalUpdates: Int) {
        setState {
            copy(
                updatesMessage = appContext.getString(
                    R.string.models_check_updates_downloading,
                    totalUpdates
                )
            )
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

    companion object : MavericksViewModelFactory<CheckUpdatesViewModel, CheckUpdatesState> {
        override fun create(
            viewModelContext: ViewModelContext,
            state: CheckUpdatesState
        ): CheckUpdatesViewModel {
            val app = viewModelContext.app<VoiceApp>()
            return CheckUpdatesViewModel(
                initialState = state,
                context = app.applicationContext,
                updateChecker = app.appGraph.modelUpdateChecker
            )
        }
    }
}
