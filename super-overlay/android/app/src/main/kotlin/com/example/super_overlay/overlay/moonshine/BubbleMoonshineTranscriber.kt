package com.example.super_overlay.overlay.moonshine

import ai.moonshine.voice.JNI
import ai.moonshine.voice.Transcriber
import android.content.Context

class BubbleMoonshineTranscriber(private val context: Context) {
    private val lock = Any()
    private var transcriber: Transcriber? = null
    private var loadedFingerprint: String? = null

    fun isModelAvailable(): Boolean {
        return MoonshineModelStore.areAllModelsPresent(context)
    }

    fun transcribeWithoutStreaming(pcm16: ShortArray, sampleRateHz: Int): String {
        if (pcm16.isEmpty()) {
            return ""
        }
        synchronized(lock) {
            val loaded = ensureLoadedLocked() ?: return ""
            val transcript = loaded.transcribeWithoutStreaming(pcm16.toFloatPcm(), sampleRateHz)
            return transcript
                .text()
                .replace(WhitespaceRegex, " ")
                .trim()
        }
    }

    fun release() {
        synchronized(lock) {
            transcriber = null
            loadedFingerprint = null
        }
    }

    private fun ensureLoadedLocked(): Transcriber? {
        if (!MoonshineModelStore.areAllModelsPresent(context)) {
            return null
        }
        val modelDir = MoonshineModelStore.modelDirectory(context)
        val fingerprint = buildModelFingerprint() ?: return null
        transcriber?.let { existing ->
            if (loadedFingerprint == fingerprint) {
                return existing
            }
        }

        val next = Transcriber()
        next.loadFromFiles(modelDir.absolutePath, JNI.MOONSHINE_MODEL_ARCH_MEDIUM_STREAMING)
        transcriber = next
        loadedFingerprint = fingerprint
        return next
    }

    private fun buildModelFingerprint(): String? {
        val parts = ArrayList<String>(MoonshineModelCatalog.mediumStreamingSpecs.size)
        for (spec in MoonshineModelCatalog.mediumStreamingSpecs) {
            val file = MoonshineModelStore.modelFile(context, spec)
            if (!file.exists()) {
                return null
            }
            parts.add("${spec.id}:${file.length()}:${file.lastModified()}")
        }
        return parts.joinToString("|")
    }

    private fun ShortArray.toFloatPcm(): FloatArray {
        val out = FloatArray(size)
        for (i in indices) {
            out[i] = this[i].toFloat() / 32768f
        }
        return out
    }

    private companion object {
        private val WhitespaceRegex = Regex("\\s+")
    }
}
