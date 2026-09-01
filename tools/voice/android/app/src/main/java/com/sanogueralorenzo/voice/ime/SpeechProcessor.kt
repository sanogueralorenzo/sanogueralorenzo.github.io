package com.sanogueralorenzo.voice.ime

import android.os.SystemClock
import android.util.Log
import com.sanogueralorenzo.voice.asr.AsrEngine
import com.sanogueralorenzo.voice.asr.AsrRuntimeStatusStore
import com.sanogueralorenzo.voice.audio.MoonshineTranscriber
import com.sanogueralorenzo.voice.audio.VoiceAudioRecorder
import com.sanogueralorenzo.voice.engine.VoiceEngine

/**
 * Speech pipeline orchestrator:
 * 1) ASR output
 * 2) Deterministic edit or append
 */
internal class SpeechProcessor(
    private val asrStage: AsrStage,
    private val textStage: TextStage
) {
    fun process(
        request: ImePipelineRequest,
        awaitChunkSessionQuiescence: (Int) -> Unit,
        finalizeMoonshineTranscript: (Int) -> String
    ): ImePipelineResult {
        val transcription = asrStage.process(
            request = request,
            awaitChunkSessionQuiescence = awaitChunkSessionQuiescence,
            finalizeMoonshineTranscript = finalizeMoonshineTranscript
        )
        val processingStartedAt = SystemClock.uptimeMillis()
        val rewrite = textStage.process(
            sourceText = request.sourceTextSnapshot,
            transcript = transcription.transcript
        )
        return ImePipelineResult(
            transcription = transcription,
            rewrite = rewrite.copy(elapsedMs = (SystemClock.uptimeMillis() - processingStartedAt))
        )
    }
}

/**
 * Stage 1: produces ASR output from captured audio with timing/path metadata.
 */
internal class AsrStage(
    private val moonshineTranscriber: MoonshineTranscriber,
    private val asrRuntimeStatusStore: AsrRuntimeStatusStore,
    private val logTag: String = "VoiceIme"
) {
    fun process(
        request: ImePipelineRequest,
        awaitChunkSessionQuiescence: (Int) -> Unit,
        finalizeMoonshineTranscript: (Int) -> String
    ): ImeTranscriptionResult {
        val startedAt = SystemClock.uptimeMillis()
        val fullPcm = request.recorder.stopAndGetPcm()
        val chunkWaitStartedAt = SystemClock.uptimeMillis()
        awaitChunkSessionQuiescence(request.chunkSessionId)
        val chunkWaitElapsedMs = SystemClock.uptimeMillis() - chunkWaitStartedAt

        val moonshineStartedAt = SystemClock.uptimeMillis()
        val streamingText = finalizeMoonshineTranscript(request.chunkSessionId)
        val moonshineElapsedMs = SystemClock.uptimeMillis() - moonshineStartedAt
        if (streamingText.isNotBlank()) {
            asrRuntimeStatusStore.recordRun(engineUsed = AsrEngine.MOONSHINE)
            val totalElapsedMs = SystemClock.uptimeMillis() - startedAt
            if (totalElapsedMs >= SLOW_TRANSCRIBE_PIPELINE_MS) {
                Log.i(
                    logTag,
                    "Moonshine transcribe pipeline slow: total=${totalElapsedMs}ms moonshine=${moonshineElapsedMs}ms chunkWait=${chunkWaitElapsedMs}ms samples=${fullPcm.size} finalChars=${streamingText.length}"
                )
            }
            return ImeTranscriptionResult(
                transcript = streamingText,
                path = TranscriptionPath.STREAMING,
                inputSamples = fullPcm.size,
                chunkWaitMs = chunkWaitElapsedMs,
                streamingFinalizeMs = moonshineElapsedMs,
                oneShotMs = 0L,
                elapsedMs = totalElapsedMs
            )
        }

        if (fullPcm.isEmpty()) {
            asrRuntimeStatusStore.recordRun(
                engineUsed = AsrEngine.MOONSHINE,
                reason = "no_audio"
            )
            return ImeTranscriptionResult(
                transcript = "",
                path = TranscriptionPath.EMPTY_AUDIO,
                inputSamples = 0,
                chunkWaitMs = chunkWaitElapsedMs,
                streamingFinalizeMs = moonshineElapsedMs,
                oneShotMs = 0L,
                elapsedMs = SystemClock.uptimeMillis() - startedAt
            )
        }

        val oneShotStartedAt = SystemClock.uptimeMillis()
        val oneShot = moonshineTranscriber.transcribeWithoutStreaming(
            pcm = fullPcm,
            sampleRateHz = VoiceAudioRecorder.SAMPLE_RATE_HZ
        )
        var oneShotElapsedMs = SystemClock.uptimeMillis() - oneShotStartedAt
        var totalElapsedMs = SystemClock.uptimeMillis() - startedAt
        if (oneShot.isNotBlank()) {
            asrRuntimeStatusStore.recordRun(
                engineUsed = AsrEngine.MOONSHINE,
                reason = "streaming_empty_non_streaming_used"
            )
            return ImeTranscriptionResult(
                transcript = oneShot,
                path = TranscriptionPath.ONE_SHOT_FALLBACK,
                inputSamples = fullPcm.size,
                chunkWaitMs = chunkWaitElapsedMs,
                streamingFinalizeMs = moonshineElapsedMs,
                oneShotMs = oneShotElapsedMs,
                elapsedMs = totalElapsedMs
            )
        }

        // First-run/cold-start can occasionally return empty; reinitialize once and retry.
        moonshineTranscriber.release()
        moonshineTranscriber.warmup()
        val retryStartedAt = SystemClock.uptimeMillis()
        val retryOneShot = moonshineTranscriber.transcribeWithoutStreaming(
            pcm = fullPcm,
            sampleRateHz = VoiceAudioRecorder.SAMPLE_RATE_HZ
        )
        oneShotElapsedMs += (SystemClock.uptimeMillis() - retryStartedAt)
        totalElapsedMs = SystemClock.uptimeMillis() - startedAt
        if (retryOneShot.isNotBlank()) {
            asrRuntimeStatusStore.recordRun(
                engineUsed = AsrEngine.MOONSHINE,
                reason = "streaming_empty_one_shot_retry_used"
            )
            return ImeTranscriptionResult(
                transcript = retryOneShot,
                path = TranscriptionPath.ONE_SHOT_RETRY,
                inputSamples = fullPcm.size,
                chunkWaitMs = chunkWaitElapsedMs,
                streamingFinalizeMs = moonshineElapsedMs,
                oneShotMs = oneShotElapsedMs,
                elapsedMs = totalElapsedMs
            )
        }

        asrRuntimeStatusStore.recordRun(
            engineUsed = AsrEngine.MOONSHINE,
            reason = "empty_after_all_paths_retry_failed"
        )
        return ImeTranscriptionResult(
            transcript = "",
            path = TranscriptionPath.EMPTY_AFTER_ALL_PATHS,
            inputSamples = fullPcm.size,
            chunkWaitMs = chunkWaitElapsedMs,
            streamingFinalizeMs = moonshineElapsedMs,
            oneShotMs = oneShotElapsedMs,
            elapsedMs = totalElapsedMs
        )
    }

    private companion object {
        private const val SLOW_TRANSCRIBE_PIPELINE_MS = 900L
    }
}

/**
 * Applies the supported deterministic edits, otherwise appends the transcript.
 */
internal class TextStage {
    fun process(
        sourceText: String,
        transcript: String
    ): ImeRewriteResult {
        val normalizedTranscript = transcript.trim()
        val hasSource = sourceText.trim().isNotBlank()
        return when {
            hasSource && VoiceEngine.isStrictEditCommand(normalizedTranscript) -> {
                processDeterministicEdit(
                    sourceText = sourceText,
                    instructionTranscript = normalizedTranscript
                )
            }

            else -> processAppend(sourceText = sourceText, transcript = normalizedTranscript)
        }
    }

    private fun processAppend(
        sourceText: String,
        transcript: String
    ): ImeRewriteResult {
        val output = appendIfNeeded(sourceText = sourceText, chunkText = transcript)
        val applied = if (sourceText.isBlank()) {
            output != transcript
        } else {
            output != sourceText
        }
        return ImeRewriteResult(
            operation = ImeOperation.APPEND,
            output = output,
            applied = applied,
            elapsedMs = 0L,
            editIntent = null
        )
    }

    private fun processDeterministicEdit(
        sourceText: String,
        instructionTranscript: String
    ): ImeRewriteResult {
        val normalizedSource = sourceText.trim()
        val normalizedInstruction = instructionTranscript.trim()
        if (normalizedSource.isBlank() || normalizedInstruction.isBlank()) {
            return ImeRewriteResult(
                operation = ImeOperation.EDIT,
                output = sourceText,
                applied = false,
                elapsedMs = 0L,
                editIntent = null
            )
        }

        val instructionAnalysis = VoiceEngine.analyzeInstruction(normalizedInstruction)
        val editIntent = instructionAnalysis.intent.name
        val deterministicEdit = VoiceEngine.tryApplyDeterministicEdit(
            sourceText = sourceText,
            instructionText = normalizedInstruction
        )
        if (deterministicEdit != null && !deterministicEdit.noMatchDetected) {
            return ImeRewriteResult(
                operation = ImeOperation.EDIT,
                output = deterministicEdit.output,
                applied = deterministicEdit.output != sourceText,
                elapsedMs = 0L,
                editIntent = deterministicEdit.intent.name
            )
        }
        return ImeRewriteResult(
            operation = ImeOperation.EDIT,
            output = sourceText,
            applied = false,
            elapsedMs = 0L,
            editIntent = editIntent
        )
    }

    private fun appendIfNeeded(
        sourceText: String,
        chunkText: String
    ): String {
        if (sourceText.isBlank()) return chunkText
        return ImeAppendFormatter.append(sourceText = sourceText, chunkText = chunkText)
    }
}
