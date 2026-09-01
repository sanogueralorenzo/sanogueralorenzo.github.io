package com.sanogueralorenzo.voice.audio

import ai.moonshine.voice.MicCaptureProcessor
import ai.moonshine.voice.MicTranscriber
import kotlin.math.sqrt

/**
 * Taps Moonshine's existing microphone samples without opening a second recorder.
 *
 * This deliberately fails fast if Moonshine changes these internals so an SDK upgrade cannot
 * silently leave the keyboard visualizer disconnected from live audio.
 */
internal object MoonshineAudioLevelTap {
    private val captureLockField = requiredField("captureLock")
    private val captureProcessorField = requiredField("micCaptureProcessor")

    fun install(transcriber: MicTranscriber, onAudioLevel: (Float) -> Unit) {
        val captureLock = checkNotNull(captureLockField.get(transcriber)) {
            "Moonshine captureLock was null after microphone start"
        }
        synchronized(captureLock) {
            val processor = captureProcessorField.get(transcriber)
            if (processor is LevelCapturingProcessor) return@synchronized
            check(processor is MicCaptureProcessor) {
                "Moonshine micCaptureProcessor was ${processor?.javaClass?.name ?: "null"} " +
                    "after microphone start"
            }
            captureProcessorField.set(
                transcriber,
                LevelCapturingProcessor(processor, onAudioLevel)
            )
        }
    }

    private fun requiredField(name: String) = MicTranscriber::class.java
        .getDeclaredField(name)
        .apply { isAccessible = true }

    private class LevelCapturingProcessor(
        private val delegate: MicCaptureProcessor,
        private val onAudioLevel: (Float) -> Unit
    ) : MicCaptureProcessor() {
        override fun consumeAudio(): FloatArray {
            return delegate.consumeAudio().also { samples ->
                if (samples.isNotEmpty()) {
                    onAudioLevel(normalizedRms(samples))
                }
            }
        }
    }

    internal fun normalizedRms(samples: FloatArray): Float {
        if (samples.isEmpty()) return 0f
        var sumOfSquares = 0.0
        samples.forEach { sample ->
            sumOfSquares += sample * sample
        }
        val rms = sqrt(sumOfSquares / samples.size).toFloat()
        return ((rms - NOISE_FLOOR_RMS) / (FULL_SCALE_RMS - NOISE_FLOOR_RMS))
            .coerceIn(0f, 1f)
    }

    private const val NOISE_FLOOR_RMS = 0.006f
    private const val FULL_SCALE_RMS = 0.08f
}
