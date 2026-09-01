package com.sanogueralorenzo.voice.asr

import android.os.SystemClock
import android.util.Log
import com.sanogueralorenzo.voice.audio.MoonshineTranscriber
import com.sanogueralorenzo.voice.audio.VoiceAudioRecorder

/** Stops a recording and returns Moonshine's transcript without rewriting it. */
class MoonshineSpeechProcessor(
    private val transcriber: MoonshineTranscriber,
    private val logTag: String = "VoiceOverlay"
) {
    fun transcribe(
        recorder: VoiceAudioRecorder,
        chunkSessionId: Int,
        awaitChunkSessionQuiescence: (Int) -> Unit,
        finalizeStreamingTranscript: (Int) -> String
    ): String {
        val startedAt = SystemClock.uptimeMillis()
        val fullPcm = recorder.stopAndGetPcm()
        val chunkWaitStartedAt = SystemClock.uptimeMillis()
        awaitChunkSessionQuiescence(chunkSessionId)
        val chunkWaitElapsedMs = SystemClock.uptimeMillis() - chunkWaitStartedAt

        val streamingStartedAt = SystemClock.uptimeMillis()
        val streamingText = finalizeStreamingTranscript(chunkSessionId)
        val streamingElapsedMs = SystemClock.uptimeMillis() - streamingStartedAt
        if (streamingText.isNotBlank()) {
            logSlowTranscription(
                startedAt = startedAt,
                streamingElapsedMs = streamingElapsedMs,
                chunkWaitElapsedMs = chunkWaitElapsedMs,
                sampleCount = fullPcm.size,
                transcriptLength = streamingText.length
            )
            return streamingText
        }

        if (fullPcm.isEmpty()) {
            return ""
        }

        val oneShot = transcriber.transcribeWithoutStreaming(
            pcm = fullPcm,
            sampleRateHz = VoiceAudioRecorder.SAMPLE_RATE_HZ
        )
        if (oneShot.isNotBlank()) {
            return oneShot
        }

        // A cold first run can occasionally be empty, so reinitialize once and retry.
        transcriber.release()
        transcriber.warmup()
        return transcriber.transcribeWithoutStreaming(
            pcm = fullPcm,
            sampleRateHz = VoiceAudioRecorder.SAMPLE_RATE_HZ
        )
    }

    private fun logSlowTranscription(
        startedAt: Long,
        streamingElapsedMs: Long,
        chunkWaitElapsedMs: Long,
        sampleCount: Int,
        transcriptLength: Int
    ) {
        val totalElapsedMs = SystemClock.uptimeMillis() - startedAt
        if (totalElapsedMs < SLOW_TRANSCRIBE_PIPELINE_MS) return
        Log.i(
            logTag,
            "Moonshine transcribe pipeline slow: total=${totalElapsedMs}ms " +
                "moonshine=${streamingElapsedMs}ms chunkWait=${chunkWaitElapsedMs}ms " +
                "samples=$sampleCount finalChars=$transcriptLength"
        )
    }

    private companion object {
        private const val SLOW_TRANSCRIBE_PIPELINE_MS = 900L
    }
}
