package com.sanogueralorenzo.voice.audio

import ai.moonshine.voice.JNI
import ai.moonshine.voice.Transcriber
import ai.moonshine.voice.TranscriberOption
import ai.moonshine.voice.TranscriptEvent
import ai.moonshine.voice.TranscriptLine
import android.content.Context
import android.util.Log
import com.sanogueralorenzo.voice.asr.MoonshineAsrProfile
import com.sanogueralorenzo.voice.asr.MoonshineAsrProfileStore
import com.sanogueralorenzo.voice.models.ModelCatalog
import com.sanogueralorenzo.voice.models.ModelStore
import java.io.File
import java.util.TreeMap
import java.util.function.Consumer

/**
 * Moonshine tiny-streaming transcriber for low-latency on-device ASR.
 *
 * This class keeps one native transcriber and one active stream session at a time.
 */
class MoonshineTranscriber(private val context: Context) {
    private val lock = Any()
    private val profileStore = MoonshineAsrProfileStore(context)
    private var transcriber: Transcriber? = null
    private var streamHandle: Int = INVALID_STREAM_HANDLE
    private var loadedProfile: MoonshineAsrProfile? = null
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
        return ModelCatalog.moonshineTinyStreamingSpecs.all {
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
            loadedProfile = null
            clearTranscriptLocked()
        }
    }

    private fun ensureLoadedLocked(): Transcriber? {
        val desiredProfile = profileStore.get()
        transcriber?.let { loaded ->
            if (loadedProfile == desiredProfile) return loaded
            closeStreamLocked(loaded)
            loaded.removeListener(listener)
            transcriber = null
            loadedProfile = null
            clearTranscriptLocked()
        }
        val modelDir = ensureModelDirectory() ?: return null
        return try {
            val loaded = Transcriber(
                optionsForProfile(desiredProfile)
            )
            loaded.loadFromFiles(modelDir.absolutePath, JNI.MOONSHINE_MODEL_ARCH_TINY_STREAMING)
            loaded.addListener(listener)
            transcriber = loaded
            loadedProfile = desiredProfile
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
        val files = ArrayList<File>(ModelCatalog.moonshineTinyStreamingSpecs.size)
        for (spec in ModelCatalog.moonshineTinyStreamingSpecs) {
            val resolved = ModelStore.ensureModelFile(context, spec) ?: return null
            files.add(resolved)
        }
        return files.firstOrNull()?.parentFile
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

    private fun optionsForProfile(profile: MoonshineAsrProfile): List<TranscriberOption> {
        return listOf(
            TranscriberOption("transcription_interval", profile.transcriptionIntervalSec),
            TranscriberOption("vad_window_duration", profile.vadWindowDurationSec),
            TranscriberOption("vad_max_segment_duration", profile.vadMaxSegmentDurationSec)
        )
    }

    companion object {
        private const val TAG = "MoonshineTranscriber"
        private const val INVALID_STREAM_HANDLE = -1
        private val WhitespaceRegex = Regex("\\s+")
    }
}
