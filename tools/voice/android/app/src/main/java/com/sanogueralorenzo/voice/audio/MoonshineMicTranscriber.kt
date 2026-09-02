package com.sanogueralorenzo.voice.audio

import ai.moonshine.voice.JNI
import ai.moonshine.voice.MicTranscriber
import ai.moonshine.voice.TranscriberOption
import ai.moonshine.voice.TranscriptLine
import android.content.Context
import android.util.Log
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelStore
import java.io.File
import java.util.function.Consumer

enum class DictationLanguage {
    ENGLISH,
    SPANISH
}

/** Owns Moonshine's microphone transcriber and exposes one active dictation session. */
class MoonshineMicTranscriber(context: Context) {
    data class Callbacks(
        val onText: (String) -> Unit,
        val onLine: (TranscriptLine) -> Unit,
        val onError: (Throwable) -> Unit,
        val onAudioLevel: ((Float) -> Unit)? = null
    )

    private val appContext = context.applicationContext
    private val lock = Any()

    @Volatile
    private var activeCallbacks: Callbacks? = null
    private var transcriber: MicTranscriber? = null
    private var loadedLanguage: DictationLanguage? = null

    fun warmup(language: DictationLanguage = DictationLanguage.ENGLISH): Boolean = synchronized(lock) {
        ensureLoadedLocked(language) != null
    }

    fun isReady(language: DictationLanguage): Boolean = modelSpecs(language).all { spec ->
        ModelStore.isModelReadyStrict(appContext, spec)
    }

    fun start(language: DictationLanguage, callbacks: Callbacks): Boolean = synchronized(lock) {
        val loaded = ensureLoadedLocked(language) ?: return false
        activeCallbacks = callbacks
        val started = runCatching {
            loaded.start()
        }.onFailure {
            activeCallbacks = null
            Log.w(TAG, "Moonshine microphone start failed", it)
        }.isSuccess
        if (started && callbacks.onAudioLevel != null) {
            MoonshineAudioLevelTap.install(loaded) { level ->
                activeCallbacks?.onAudioLevel?.invoke(level)
            }
        }
        started
    }

    fun stop() = synchronized(lock) {
        runCatching { transcriber?.stop() }
            .onFailure { Log.w(TAG, "Moonshine microphone stop failed", it) }
        Unit
    }

    fun detachCallbacks() {
        activeCallbacks = null
    }

    fun cancel() {
        detachCallbacks()
        stop()
    }

    /** Releases Moonshine's persistent microphone capture, then reloads without recording. */
    fun releaseMicrophoneAndWarmup(language: DictationLanguage): Boolean = synchronized(lock) {
        closeLocked()
        ensureLoadedLocked(language) != null
    }

    fun close() = synchronized(lock) {
        closeLocked()
    }

    private fun closeLocked() {
        activeCallbacks = null
        runCatching { transcriber?.close() }
            .onFailure { Log.w(TAG, "Moonshine close failed", it) }
        transcriber = null
        loadedLanguage = null
    }

    private fun ensureLoadedLocked(language: DictationLanguage): MicTranscriber? {
        if (loadedLanguage == language) {
            transcriber?.let { return it }
        }
        val modelDirectory = ensureModelDirectory(language) ?: return null
        runCatching { transcriber?.close() }
            .onFailure { Log.w(TAG, "Moonshine model switch close failed", it) }
        transcriber = null
        loadedLanguage = null
        val configuration = modelConfiguration(language)
        return runCatching {
            MicTranscriber(appContext)
                .language(configuration.languageCode)
                .modelArch(configuration.architecture)
                .options(OPTIONS)
                .callbacksOnMainThread(true)
                .onText(Consumer { text -> activeCallbacks?.onText?.invoke(text) })
                .onLine(Consumer { line -> activeCallbacks?.onLine?.invoke(line) })
                .onError(Consumer { error -> activeCallbacks?.onError?.invoke(error) })
                .also { mic ->
                    mic.loadFromFiles(
                        modelDirectory.absolutePath,
                        configuration.architecture
                    )
                    transcriber = mic
                    loadedLanguage = language
                }
        }.onFailure {
            Log.w(TAG, "Moonshine load failed", it)
        }.getOrNull()
    }

    private fun ensureModelDirectory(language: DictationLanguage): File? {
        val modelFiles = modelSpecs(language).map { spec ->
            ModelStore.ensureModelFile(appContext, spec) ?: return null
        }
        return modelFiles.firstOrNull()?.parentFile
    }

    private fun modelSpecs(language: DictationLanguage) =
        ModelCatalog.moonshineStreamingSpecsFor(language)

    private fun modelConfiguration(language: DictationLanguage) = when (language) {
        DictationLanguage.ENGLISH -> ModelConfiguration(
            languageCode = "en",
            architecture = JNI.MOONSHINE_MODEL_ARCH_MEDIUM_STREAMING
        )

        DictationLanguage.SPANISH -> ModelConfiguration(
            languageCode = "es",
            architecture = JNI.MOONSHINE_MODEL_ARCH_SMALL_STREAMING
        )
    }

    private data class ModelConfiguration(
        val languageCode: String,
        val architecture: Int
    )

    private companion object {
        private const val TAG = "MoonshineMic"
        private val OPTIONS = listOf(
            TranscriberOption("transcription_interval", "0.5"),
            TranscriberOption("vad_threshold", "0.5"),
            TranscriberOption("vad_window_duration", "0.5"),
            TranscriberOption("vad_look_behind_sample_count", "8192"),
            TranscriberOption("vad_max_segment_duration", "15.0"),
            TranscriberOption("max_tokens_per_second", "6.5")
        )
    }
}
