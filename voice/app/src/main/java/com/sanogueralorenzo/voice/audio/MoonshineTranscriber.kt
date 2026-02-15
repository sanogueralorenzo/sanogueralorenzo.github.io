package com.sanogueralorenzo.voice.audio

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

/**
 * Moonshine medium-streaming transcriber for higher-accuracy on-device ASR.
 *
 * This class keeps one native transcriber and one active stream session at a time.
 */
class MoonshineTranscriber(private val context: Context) {
    private val lock = Any()
    private var transcriber: Transcriber? = null
    private var streamHandle: Int = INVALID_STREAM_HANDLE
    private var loadedModelFingerprint: String? = null
    private val linesById = LinkedHashMap<Long, String>()
    private val listener = Consumer<TranscriptEvent> { event ->
        when (event) {
            is TranscriptEvent.LineStarted -> onLine(event.line)
            is TranscriptEvent.LineUpdated -> onLine(event.line)
            is TranscriptEvent.LineTextChanged -> onLine(event.line)
            is TranscriptEvent.LineCompleted -> onLine(event.line)
            is TranscriptEvent.Error -> Log.w(TAG, "Moonshine stream error", event.cause)
        }
    }

    fun isModelAvailable(): Boolean {
        return ModelCatalog.moonshineMediumStreamingSpecs.all {
            ModelStore.isModelPresent(context, it)
        }
    }

    fun warmup(): Boolean {
        synchronized(lock) {
            return ensureLoadedLocked() != null
        }
    }

    fun startSession(): Boolean {
        synchronized(lock) {
            val loaded = ensureLoadedLocked() ?: return false
            clearTranscriptLocked()
            closeStreamLocked(loaded)
            val created = loaded.createStream()
            if (created < 0) {
                Log.w(TAG, "Moonshine createStream failed: $created")
                streamHandle = INVALID_STREAM_HANDLE
                return false
            }
            streamHandle = created
            val started = runCatching { loaded.startStream(streamHandle) }
                .onFailure { Log.w(TAG, "Moonshine startStream failed", it) }
                .isSuccess
            return started && streamHandle >= 0
        }
    }

    fun addAudio(pcm: ShortArray, sampleRateHz: Int) {
        if (pcm.isEmpty()) return
        synchronized(lock) {
            val loaded = ensureLoadedLocked() ?: return
            ensureSessionLocked(loaded)
            if (streamHandle < 0) return
            runCatching {
                loaded.addAudioToStream(
                    streamHandle,
                    pcm.toFloatPcm(),
                    sampleRateHz
                )
            }.onFailure {
                Log.w(TAG, "Moonshine addAudioToStream failed", it)
            }
        }
    }

    fun stopSessionAndGetTranscript(): String {
        synchronized(lock) {
            val loaded = transcriber ?: return ""
            closeStreamLocked(loaded)
            return buildTranscriptLocked()
        }
    }

    fun transcribeWithoutStreaming(pcm: ShortArray, sampleRateHz: Int): String {
        if (pcm.isEmpty()) return ""
        synchronized(lock) {
            val loaded = ensureLoadedLocked() ?: return ""
            return runCatching {
                loaded.transcribeWithoutStreaming(pcm.toFloatPcm(), sampleRateHz).text().trim()
            }.onFailure {
                Log.w(TAG, "Moonshine transcribeWithoutStreaming failed", it)
            }.getOrDefault("")
        }
    }

    fun cancelActive() {
        synchronized(lock) {
            val loaded = transcriber ?: return
            closeStreamLocked(loaded)
            clearTranscriptLocked()
        }
    }

    fun release() {
        synchronized(lock) {
            val loaded = transcriber ?: return
            closeStreamLocked(loaded)
            loaded.removeListener(listener)
            transcriber = null
            loadedModelFingerprint = null
            clearTranscriptLocked()
        }
    }

    private fun ensureLoadedLocked(): Transcriber? {
        val modelDir = ensureModelDirectory() ?: return null
        val fingerprint = modelFingerprintForCurrentSpecs() ?: return null
        transcriber?.let { loaded ->
            if (loadedModelFingerprint == fingerprint) {
                return loaded
            }
            closeStreamLocked(loaded)
            runCatching { loaded.removeListener(listener) }
            transcriber = null
            loadedModelFingerprint = null
            clearTranscriptLocked()
        }
        return try {
            val loaded = Transcriber(
                listOf(
                    // Moonshine-documented defaults favor stability/accuracy.
                    TranscriberOption("transcription_interval", "0.5"),
                    TranscriberOption("vad_threshold", "0.5"),
                    TranscriberOption("vad_window_duration", "0.5"),
                    TranscriberOption("vad_look_behind_sample_count", "8192"),
                    TranscriberOption("vad_max_segment_duration", "15.0"),
                    TranscriberOption("max_tokens_per_second", "6.5")
                )
            )
            loaded.loadFromFiles(modelDir.absolutePath, JNI.MOONSHINE_MODEL_ARCH_MEDIUM_STREAMING)
            loaded.addListener(listener)
            transcriber = loaded
            loadedModelFingerprint = fingerprint
            loaded
        } catch (t: Throwable) {
            Log.w(TAG, "Moonshine load failed", t)
            null
        }
    }

    private fun ensureSessionLocked(loaded: Transcriber) {
        if (streamHandle >= 0) return
        val created = loaded.createStream()
        if (created < 0) {
            Log.w(TAG, "Moonshine createStream failed: $created")
            return
        }
        streamHandle = created
        runCatching { loaded.startStream(streamHandle) }
            .onFailure { Log.w(TAG, "Moonshine startStream failed", it) }
    }

    private fun closeStreamLocked(loaded: Transcriber) {
        val handle = streamHandle
        if (handle < 0) return
        runCatching { loaded.stopStream(handle) }
            .onFailure { Log.w(TAG, "Moonshine stopStream failed", it) }
        runCatching { loaded.freeStream(handle) }
            .onFailure { Log.w(TAG, "Moonshine freeStream failed", it) }
        streamHandle = INVALID_STREAM_HANDLE
    }

    private fun ensureModelDirectory(): File? {
        val files = ArrayList<File>(ModelCatalog.moonshineMediumStreamingSpecs.size)
        for (spec in ModelCatalog.moonshineMediumStreamingSpecs) {
            val resolved = ModelStore.ensureModelFile(context, spec) ?: return null
            files.add(resolved)
        }
        return files.firstOrNull()?.parentFile
    }

    private fun modelFingerprintForCurrentSpecs(): String? {
        val parts = ArrayList<String>(ModelCatalog.moonshineMediumStreamingSpecs.size)
        for (spec in ModelCatalog.moonshineMediumStreamingSpecs) {
            val file = ModelStore.modelFile(context, spec)
            if (!file.exists()) return null
            parts.add("${spec.id}:${file.length()}:${file.lastModified()}")
        }
        return parts.joinToString("|")
    }

    private fun onLine(line: TranscriptLine?) {
        if (line == null) return
        val text = line.text?.trim().orEmpty()
        if (text.isBlank()) return
        synchronized(lock) {
            linesById[line.id] = text
        }
    }

    private fun clearTranscriptLocked() {
        linesById.clear()
    }

    private fun buildTranscriptLocked(): String {
        if (linesById.isEmpty()) return ""
        return TreeMap(linesById)
            .values
            .joinToString(" ")
            .replace(WhitespaceRegex, " ")
            .trim()
    }

    private fun ShortArray.toFloatPcm(): FloatArray {
        val out = FloatArray(size)
        for (i in indices) {
            out[i] = this[i].toFloat() / 32768f
        }
        return out
    }

    companion object {
        private const val TAG = "MoonshineTranscriber"
        private const val INVALID_STREAM_HANDLE = -1
        private val WhitespaceRegex = Regex("\\s+")
    }
}
