package com.sanogueralorenzo.voice.keyboard

import ai.moonshine.voice.JNI
import ai.moonshine.voice.Transcriber
import ai.moonshine.voice.TranscriberOption
import ai.moonshine.voice.TranscriptEvent
import ai.moonshine.voice.TranscriptLine
import android.content.Context
import android.util.Log
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelStore
import java.io.File
import java.util.TreeMap
import java.util.function.Consumer

/** Streaming Moonshine session owned by the compact keyboard product. */
internal class KeyboardMoonshineTranscriber(context: Context) {
    private val appContext = context.applicationContext
    private val lock = Any()
    private var transcriber: Transcriber? = null
    private var streamHandle = INVALID_STREAM_HANDLE
    private val linesById = LinkedHashMap<Long, String>()
    private val listener = Consumer<TranscriptEvent> { event ->
        when (event) {
            is TranscriptEvent.LineStarted -> recordLine(event.line)
            is TranscriptEvent.LineUpdated -> recordLine(event.line)
            is TranscriptEvent.LineTextChanged -> recordLine(event.line)
            is TranscriptEvent.LineCompleted -> recordLine(event.line)
            is TranscriptEvent.Error -> Log.w(TAG, "Moonshine stream error", event.cause)
        }
    }

    fun warmup(): Boolean = synchronized(lock) { ensureLoadedLocked() != null }

    fun startSession(): Boolean = synchronized(lock) {
        val loaded = ensureLoadedLocked() ?: return false
        clearTranscriptLocked()
        closeStreamLocked(loaded)
        val handle = loaded.createStream()
        if (handle < 0) return false
        streamHandle = handle
        runCatching { loaded.startStream(handle) }
            .onFailure { Log.w(TAG, "Moonshine stream start failed", it) }
            .isSuccess
    }

    fun addAudio(pcm: ShortArray) {
        if (pcm.isEmpty()) return
        synchronized(lock) {
            val loaded = transcriber ?: return
            if (streamHandle < 0) return
            runCatching {
                loaded.addAudioToStream(
                    streamHandle,
                    pcm.toFloatPcm(),
                    KeyboardAudioRecorder.SAMPLE_RATE_HZ
                )
            }.onFailure { Log.w(TAG, "Moonshine audio frame failed", it) }
        }
    }

    fun finishSession(): String = synchronized(lock) {
        val loaded = transcriber ?: return ""
        closeStreamLocked(loaded)
        buildTranscriptLocked()
    }

    fun transcribeOneShot(pcm: ShortArray): String {
        if (pcm.isEmpty()) return ""
        return synchronized(lock) {
            val loaded = ensureLoadedLocked() ?: return ""
            runCatching {
                loaded.transcribeWithoutStreaming(
                    pcm.toFloatPcm(),
                    KeyboardAudioRecorder.SAMPLE_RATE_HZ
                ).text().trim()
            }.onFailure { Log.w(TAG, "Moonshine one-shot fallback failed", it) }
                .getOrDefault("")
        }
    }

    fun cancelActive() {
        synchronized(lock) {
            transcriber?.let(::closeStreamLocked)
            clearTranscriptLocked()
        }
    }

    fun close() {
        synchronized(lock) {
            val loaded = transcriber ?: return
            closeStreamLocked(loaded)
            runCatching { loaded.removeListener(listener) }
            transcriber = null
            clearTranscriptLocked()
        }
    }

    private fun ensureLoadedLocked(): Transcriber? {
        transcriber?.let { return it }
        val modelDirectory = ensureModelDirectory() ?: return null
        return runCatching {
            Transcriber(OPTIONS).also { loaded ->
                loaded.loadFromFiles(
                    modelDirectory.absolutePath,
                    JNI.MOONSHINE_MODEL_ARCH_MEDIUM_STREAMING
                )
                loaded.addListener(listener)
                transcriber = loaded
            }
        }.onFailure { Log.w(TAG, "Moonshine load failed", it) }
            .getOrNull()
    }

    private fun ensureModelDirectory(): File? {
        val modelFiles = ModelCatalog.moonshineMediumStreamingSpecs.map { spec ->
            ModelStore.ensureModelFile(appContext, spec) ?: return null
        }
        return modelFiles.firstOrNull()?.parentFile
    }

    private fun closeStreamLocked(loaded: Transcriber) {
        val handle = streamHandle
        if (handle < 0) return
        runCatching { loaded.stopStream(handle) }
        runCatching { loaded.freeStream(handle) }
        streamHandle = INVALID_STREAM_HANDLE
    }

    private fun recordLine(line: TranscriptLine?) {
        val text = line?.text?.trim().orEmpty()
        if (text.isBlank() || line == null) return
        synchronized(lock) { linesById[line.id] = text }
    }

    private fun clearTranscriptLocked() {
        linesById.clear()
    }

    private fun buildTranscriptLocked(): String {
        return TreeMap(linesById)
            .values
            .joinToString(" ")
            .replace(WHITESPACE_REGEX, " ")
            .trim()
    }

    private fun ShortArray.toFloatPcm(): FloatArray {
        return FloatArray(size) { index -> this[index].toFloat() / 32768f }
    }

    private companion object {
        const val TAG = "VoiceKeyboardASR"
        const val INVALID_STREAM_HANDLE = -1
        val WHITESPACE_REGEX = Regex("\\s+")
        val OPTIONS = listOf(
            TranscriberOption("transcription_interval", "0.5"),
            TranscriberOption("vad_threshold", "0.5"),
            TranscriberOption("vad_window_duration", "0.5"),
            TranscriberOption("vad_look_behind_sample_count", "8192"),
            TranscriberOption("vad_max_segment_duration", "15.0"),
            TranscriberOption("max_tokens_per_second", "6.5")
        )
    }
}
