package com.sanogueralorenzo.voice.models

import android.content.Context
import com.sanogueralorenzo.voice.R
import com.sanogueralorenzo.voice.audio.DictationLanguage
import com.sanogueralorenzo.voice.audio.DictationLanguagePreferences
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import kotlin.coroutines.resume
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

data class LanguageModelStatus(
    val language: DictationLanguage,
    val orderIndex: Int? = null,
    val ready: Boolean = false,
    val downloading: Boolean = false,
    val progress: Int = 0,
    val error: String? = null
)

data class LocalModelsStatus(
    val loading: Boolean = true,
    val models: List<LanguageModelStatus> = DictationLanguage.entries.map(::LanguageModelStatus)
) {
    val downloadedCount: Int get() = models.count { it.ready }
    val operationInProgress: Boolean get() = models.any { it.downloading }
    val downloadedLanguages: Set<DictationLanguage>
        get() = models.filterTo(linkedSetOf(), LanguageModelStatus::ready)
            .mapTo(linkedSetOf(), LanguageModelStatus::language)
}

/** Owns local-model readiness, download progress, and tap/long-press language ordering. */
@Inject
@SingleIn(AppScope::class)
class LocalModelsRepository(
    context: Context,
    private val languagePreferences: DictationLanguagePreferences
) {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mutableStatus = MutableStateFlow(LocalModelsStatus())

    val status: StateFlow<LocalModelsStatus> = mutableStatus.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        if (mutableStatus.value.operationInProgress) return
        scope.launch {
            val readiness = withContext(Dispatchers.IO) {
                DictationLanguage.entries.associateWith(::isReady)
            }
            val ordered = languagePreferences.syncDownloaded(
                readiness.filterValues { it }.keys
            )
            mutableStatus.value = LocalModelsStatus(
                loading = false,
                models = buildModelStatuses(ordered, readiness)
            )
        }
    }

    fun readDownloadedLanguages(): Set<DictationLanguage> {
        return DictationLanguage.entries.filterTo(linkedSetOf()) { isReady(it) }
    }

    fun swapLanguages() {
        val current = mutableStatus.value
        if (current.loading || current.operationInProgress) return
        val downloaded = current.models.filter(LanguageModelStatus::ready)
        if (downloaded.size != 2) return
        val ordering = languagePreferences.swap(
            downloaded[0].language,
            downloaded[1].language
        )
        mutableStatus.value = current.copy(
            models = current.models.withOrdering(ordering.ordered)
        )
    }

    fun download(language: DictationLanguage) {
        val current = mutableStatus.value
        val canStart = !current.loading && !current.operationInProgress &&
            current.models.any { it.language == language && !it.ready }
        if (!canStart) return

        mutableStatus.value = current.copy(
            models = current.models.update(language) {
                copy(downloading = true, progress = 0, error = null)
            }
        )
        scope.launch {
            val downloader = ModelDownloader(appContext)
            val result = try {
                downloadLanguage(language, downloader)
            } finally {
                downloader.shutdown()
            }
            when (result) {
                null -> {
                    val downloaded = mutableStatus.value.models
                        .filter(LanguageModelStatus::ready)
                        .mapTo(mutableSetOf(), LanguageModelStatus::language) + language
                    val ordered = languagePreferences.syncDownloaded(downloaded)
                    mutableStatus.value = mutableStatus.value.copy(
                        models = mutableStatus.value.models.update(language) {
                            copy(
                                ready = true,
                                downloading = false,
                                progress = 100,
                                error = null
                            )
                        }.withOrdering(ordered)
                    )
                }

                else -> mutableStatus.value = mutableStatus.value.copy(
                    models = mutableStatus.value.models.update(language) {
                        copy(downloading = false, error = result)
                    }
                )
            }
        }
    }

    private fun isReady(language: DictationLanguage): Boolean {
        return ModelCatalog.moonshineStreamingSpecsFor(language).all { spec ->
            ModelStore.isModelReadyStrict(appContext, spec)
        }
    }

    /** Returns an error message, or null after a successful download. */
    private suspend fun downloadLanguage(
        language: DictationLanguage,
        downloader: ModelDownloader
    ): String? {
        val specs = ModelCatalog.moonshineStreamingSpecsFor(language)
        val readyModels = withContext(Dispatchers.IO) {
            specs.associateWith { spec -> ModelStore.isModelReadyStrict(appContext, spec) }
        }
        val weights = specs.associateWith { it.sizeBytes.coerceAtLeast(1L) }
        val totalWeight = weights.values.sum()
        var completedWeight = specs.sumOf { spec ->
            if (readyModels.getValue(spec)) weights.getValue(spec) else 0L
        }

        fun reportProgress(currentWeight: Long = 0L, currentPercent: Int = 0) {
            val partial = currentWeight.toDouble() * currentPercent.coerceIn(0, 100) / 100.0
            val percent = (((completedWeight + partial) / totalWeight) * 100.0)
                .toInt()
                .coerceIn(0, 100)
            mutableStatus.value = mutableStatus.value.copy(
                models = mutableStatus.value.models.update(language) { copy(progress = percent) }
            )
        }

        reportProgress()
        for (spec in specs) {
            if (readyModels.getValue(spec)) continue
            val weight = weights.getValue(spec)
            val result = downloader.downloadAwait(spec) { percent ->
                reportProgress(currentWeight = weight, currentPercent = percent)
            }
            if (!result.isSuccess) return modelErrorMessage(spec, result)
            completedWeight += weight
            reportProgress()
        }
        reportProgress()
        return null
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
            ModelDownloadResult.AlreadyAvailable -> error("Successful downloads have no error.")

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

    private fun buildModelStatuses(
        ordered: List<DictationLanguage>,
        readiness: Map<DictationLanguage, Boolean>
    ): List<LanguageModelStatus> {
        return DictationLanguage.entries.map { language ->
            LanguageModelStatus(
                language = language,
                orderIndex = ordered.indexOf(language).takeIf { it >= 0 },
                ready = readiness[language] == true
            )
        }.sortedWith(modelOrderComparator)
    }

    private fun List<LanguageModelStatus>.withOrdering(
        ordered: List<DictationLanguage>
    ): List<LanguageModelStatus> {
        return map { model ->
            model.copy(orderIndex = ordered.indexOf(model.language).takeIf { it >= 0 })
        }.sortedWith(modelOrderComparator)
    }

    private fun List<LanguageModelStatus>.update(
        language: DictationLanguage,
        transform: LanguageModelStatus.() -> LanguageModelStatus
    ): List<LanguageModelStatus> = map { model ->
        if (model.language == language) model.transform() else model
    }

    private companion object {
        val modelOrderComparator = compareBy<LanguageModelStatus>(
            { it.orderIndex == null },
            { it.orderIndex ?: Int.MAX_VALUE },
            { it.language.ordinal }
        )
    }
}

private val ModelDownloadResult.isSuccess: Boolean
    get() = this is ModelDownloadResult.Success || this is ModelDownloadResult.AlreadyAvailable
