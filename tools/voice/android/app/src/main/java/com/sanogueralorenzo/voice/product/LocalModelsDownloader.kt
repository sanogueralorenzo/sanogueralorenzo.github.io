package com.sanogueralorenzo.voice.product

import android.content.Context
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelDownloadResult
import com.sanogueralorenzo.voice.models.ModelDownloader
import com.sanogueralorenzo.voice.models.ModelSetupRepository
import com.sanogueralorenzo.voice.models.ModelSpec
import com.sanogueralorenzo.voice.models.ModelStore
import com.sanogueralorenzo.voice.prompt.PromptTemplateStore
import com.sanogueralorenzo.voice.summary.LiteRtRuntimeConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume

sealed interface LocalModelsDownloadResult {
    data object Success : LocalModelsDownloadResult
    data class Failure(val message: String) : LocalModelsDownloadResult
}

/** Owns the complete local-model download so product UI only starts it and observes progress. */
class LocalModelsDownloader(
    context: Context,
    private val modelSetupRepository: ModelSetupRepository
) {
    private val appContext = context.applicationContext

    suspend fun download(onProgress: (Int) -> Unit): LocalModelsDownloadResult {
        val downloader = ModelDownloader(appContext)
        return try {
            downloadLocalAssets(downloader, onProgress)
        } finally {
            downloader.shutdown()
        }
    }

    private suspend fun downloadLocalAssets(
        downloader: ModelDownloader,
        onProgress: (Int) -> Unit
    ): LocalModelsDownloadResult {
        val modelSpecs = ModelCatalog.moonshineMediumStreamingSpecs +
            listOfNotNull(ModelCatalog.liteRtLm.takeIf { LiteRtRuntimeConfig.ENABLE_LLM })
        val readyModels = withContext(Dispatchers.IO) {
            modelSpecs.associateWith { spec ->
                ModelStore.isModelReadyStrict(appContext, spec)
            }
        }
        val promptReady = !LiteRtRuntimeConfig.ENABLE_LLM || withContext(Dispatchers.IO) {
            modelSetupRepository.readModelReadiness().promptReady
        }
        val modelWeights = modelSpecs.associateWith { it.sizeBytes.coerceAtLeast(1L) }
        val totalModelWeight = modelWeights.values.sum()
        val promptWeight = if (LiteRtRuntimeConfig.ENABLE_LLM) {
            (totalModelWeight / 99L).coerceAtLeast(1L)
        } else {
            0L
        }
        val totalWeight = totalModelWeight + promptWeight
        var completedWeight = modelSpecs.sumOf { spec ->
            if (readyModels.getValue(spec)) modelWeights.getValue(spec) else 0L
        } + if (promptReady) promptWeight else 0L

        fun reportProgress(currentWeight: Long = 0L, currentPercent: Int = 0) {
            val currentCompleted = currentWeight.toDouble() *
                (currentPercent.coerceIn(0, 100).toDouble() / 100.0)
            val percent = (((completedWeight.toDouble() + currentCompleted) / totalWeight) * 100.0)
                .toInt()
                .coerceIn(0, 100)
            onProgress(percent)
        }

        reportProgress()
        for (spec in modelSpecs) {
            if (readyModels.getValue(spec)) continue
            val weight = modelWeights.getValue(spec)
            val result = downloader.downloadAwait(spec) { percent ->
                reportProgress(currentWeight = weight, currentPercent = percent)
            }
            if (!result.isSuccess) {
                return LocalModelsDownloadResult.Failure(modelErrorMessage(spec, result))
            }
            completedWeight += weight
            reportProgress()
        }

        if (!promptReady) {
            val result = modelSetupRepository.ensurePromptDownloaded(force = false)
            if (!result.isSuccess) {
                return LocalModelsDownloadResult.Failure(promptErrorMessage(result))
            }
            completedWeight += promptWeight
        }

        onProgress(100)
        return LocalModelsDownloadResult.Success
    }

    private suspend fun ModelDownloader.downloadAwait(
        spec: ModelSpec,
        onProgress: (Int) -> Unit
    ): ModelDownloadResult = suspendCancellableCoroutine { continuation ->
        download(
            spec = spec,
            onProgress = onProgress,
            onComplete = { result ->
                if (continuation.isActive) continuation.resume(result)
            }
        )
    }

    private fun modelErrorMessage(spec: ModelSpec, result: ModelDownloadResult): String {
        return when (result) {
            ModelDownloadResult.Success,
            ModelDownloadResult.AlreadyAvailable -> error("Successful downloads do not have an error message.")

            is ModelDownloadResult.HttpError -> appContext.getString(
                R.string.product_models_error_http,
                spec.id,
                result.code
            )

            is ModelDownloadResult.HashMismatch -> appContext.getString(
                R.string.product_models_error_hash,
                spec.id
            )

            is ModelDownloadResult.SizeMismatch -> appContext.getString(
                R.string.product_models_error_size,
                spec.id
            )

            is ModelDownloadResult.NetworkError -> appContext.getString(
                R.string.product_models_error_network,
                spec.id
            )

            is ModelDownloadResult.StorageError -> appContext.getString(
                R.string.product_models_error_storage,
                spec.id
            )

            is ModelDownloadResult.UnknownError -> appContext.getString(
                R.string.product_models_error_unknown,
                spec.id
            )

            ModelDownloadResult.InvalidSpec -> appContext.getString(
                R.string.product_models_error_invalid,
                spec.id
            )
        }
    }

    private fun promptErrorMessage(result: PromptTemplateStore.DownloadResult): String {
        return when (result) {
            is PromptTemplateStore.DownloadResult.Success,
            is PromptTemplateStore.DownloadResult.AlreadyAvailable ->
                error("Successful downloads do not have an error message.")

            is PromptTemplateStore.DownloadResult.HttpError -> appContext.getString(
                R.string.product_prompt_error_http,
                result.code
            )

            is PromptTemplateStore.DownloadResult.NetworkError ->
                appContext.getString(R.string.product_prompt_error_network)

            is PromptTemplateStore.DownloadResult.InvalidPayload ->
                appContext.getString(R.string.product_prompt_error_invalid)

            is PromptTemplateStore.DownloadResult.StorageError ->
                appContext.getString(R.string.product_prompt_error_storage)

            is PromptTemplateStore.DownloadResult.UnknownError ->
                appContext.getString(R.string.product_prompt_error_unknown)
        }
    }
}

private val ModelDownloadResult.isSuccess: Boolean
    get() = this is ModelDownloadResult.Success || this is ModelDownloadResult.AlreadyAvailable

private val PromptTemplateStore.DownloadResult.isSuccess: Boolean
    get() = this is PromptTemplateStore.DownloadResult.Success ||
        this is PromptTemplateStore.DownloadResult.AlreadyAvailable
