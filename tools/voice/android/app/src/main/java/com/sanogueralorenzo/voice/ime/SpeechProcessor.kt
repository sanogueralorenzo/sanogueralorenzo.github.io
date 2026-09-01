package com.sanogueralorenzo.voice.ime

import android.os.SystemClock
import android.util.Log
import com.sanogueralorenzo.voice.asr.AsrEngine
import com.sanogueralorenzo.voice.asr.AsrRuntimeStatusStore
import com.sanogueralorenzo.voice.audio.MoonshineTranscriber
import com.sanogueralorenzo.voice.audio.VoiceAudioRecorder
import com.sanogueralorenzo.voice.command.LlmCommand
import com.sanogueralorenzo.voice.engine.VoiceEngine
import com.sanogueralorenzo.voice.preferences.PreferencesRepository
import com.sanogueralorenzo.voice.summary.RewriteResult
import com.sanogueralorenzo.voice.summary.SummaryEngine

/**
 * 4-stage speech pipeline orchestrator:
 * 1) ASR output
 * 2) Pre-LLM local rules (rule decisions before model)
 * 3) LLM output
 * 4) Post-LLM local rules (final normalization/guards)
 */
internal class SpeechProcessor(
    private val asrStage: AsrStage,
    private val preLlmRulesStage: PreLlmRulesStage,
    private val llmStage: LlmStage,
    private val postLlmRulesStage: PostLlmRulesStage
) {
    fun process(
        request: ImePipelineRequest,
        awaitChunkSessionQuiescence: (Int) -> Unit,
        finalizeMoonshineTranscript: (Int) -> String,
        onShowRewriting: () -> Unit
    ): ImePipelineResult {
        val transcription = asrStage.process(
            request = request,
            awaitChunkSessionQuiescence = awaitChunkSessionQuiescence,
            finalizeMoonshineTranscript = finalizeMoonshineTranscript
        )
        val rewriteStartedAt = SystemClock.uptimeMillis()
        val preLlm = preLlmRulesStage.process(
            sourceText = request.sourceTextSnapshot,
            transcript = transcription.transcript
        )
        val rewrite = when (preLlm) {
            is PreLlmResult.Complete -> postLlmRulesStage.processComplete(preLlm)
            is PreLlmResult.NeedsEditLlm -> {
                val llm = llmStage.processEdit(preLlm, onShowRewriting)
                postLlmRulesStage.processEdit(preLlm, llm)
            }
        }
        return ImePipelineResult(
            transcription = transcription,
            rewrite = rewrite.copy(elapsedMs = (SystemClock.uptimeMillis() - rewriteStartedAt))
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
 * Stage 2: applies deterministic/local rules before any LLM call and decides
 * whether processing can complete locally or should continue to Stage 3.
 */
internal class PreLlmRulesStage(
    private val preferencesRepository: PreferencesRepository,
    private val summaryEngine: SummaryEngine
) {
    fun process(
        sourceText: String,
        transcript: String
    ): PreLlmResult {
        val normalizedTranscript = transcript.trim()
        val hasSource = sourceText.trim().isNotBlank()
        val llmCommand = LlmCommand.fromExactTranscript(normalizedTranscript)
        return when {
            hasSource && VoiceEngine.isStrictEditCommand(normalizedTranscript) -> {
                processDeterministicEdit(
                    sourceText = sourceText,
                    instructionTranscript = normalizedTranscript
                )
            }

            hasSource && llmCommand != null -> {
                processLlmCommand(sourceText = sourceText, command = llmCommand)
            }

            else -> processAppend(sourceText = sourceText, transcript = normalizedTranscript)
        }
    }

    private fun processAppend(
        sourceText: String,
        transcript: String
    ): PreLlmResult {
        val deterministicResult = VoiceEngine.preprocess(transcript)
        val localRules = deterministicResult.appliedRuleIds.map { ruleId ->
            "compose_${ruleId.lowercase()}"
        }
        val output = appendIfNeeded(sourceText = sourceText, chunkText = transcript)
        val applied = if (sourceText.isBlank()) {
            output != transcript
        } else {
            output != sourceText
        }
        return PreLlmResult.Complete(
            operation = ImeOperation.APPEND,
            output = output,
            applied = applied,
            editIntent = null,
            diagnostics = ImeRewriteDiagnostics(localRulesBeforeLlm = localRules)
        )
    }

    private fun processDeterministicEdit(
        sourceText: String,
        instructionTranscript: String
    ): PreLlmResult {
        val localRulesBeforeLlm = mutableListOf("strict_edit_command")
        val diagnostics = ImeRewriteDiagnostics(localRulesBeforeLlm = localRulesBeforeLlm)
        val normalizedSource = sourceText.trim()
        val normalizedInstruction = instructionTranscript.trim()
        if (normalizedSource.isBlank() || normalizedInstruction.isBlank()) {
            return PreLlmResult.Complete(
                operation = ImeOperation.EDIT,
                output = sourceText,
                applied = false,
                editIntent = null,
                diagnostics = diagnostics
            )
        }

        val instructionAnalysis = VoiceEngine.analyzeInstruction(normalizedInstruction)
        val editIntent = instructionAnalysis.intent.name
        val deterministicEdit = VoiceEngine.tryApplyDeterministicEdit(
            sourceText = sourceText,
            instructionText = normalizedInstruction
        )
        if (deterministicEdit != null && !deterministicEdit.noMatchDetected) {
            localRulesBeforeLlm += "deterministic_${deterministicEdit.commandKind.name.lowercase()}"
            return PreLlmResult.Complete(
                operation = ImeOperation.EDIT,
                output = deterministicEdit.output,
                applied = deterministicEdit.output != sourceText,
                editIntent = deterministicEdit.intent.name,
                diagnostics = diagnostics
            )
        }
        if (deterministicEdit?.noMatchDetected == true) {
            localRulesBeforeLlm += "deterministic_no_match"
        }
        return PreLlmResult.Complete(
            operation = ImeOperation.EDIT,
            output = sourceText,
            applied = false,
            editIntent = editIntent,
            diagnostics = diagnostics
        )
    }

    private fun processLlmCommand(
        sourceText: String,
        command: LlmCommand
    ): PreLlmResult {
        val diagnostics = ImeRewriteDiagnostics(
            localRulesBeforeLlm = listOf("llm_command_${command.name.lowercase()}")
        )
        if (!preferencesRepository.isLlmRewriteEnabled() || !summaryEngine.isModelAvailable()) {
            return PreLlmResult.Complete(
                operation = ImeOperation.EDIT,
                output = sourceText,
                applied = false,
                editIntent = VoiceEngine.EditIntent.GENERAL.name,
                diagnostics = diagnostics
            )
        }
        return PreLlmResult.NeedsEditLlm(
            sourceText = sourceText,
            instruction = command.name,
            editIntent = VoiceEngine.EditIntent.GENERAL.name,
            diagnostics = diagnostics
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

/**
 * Stage 3: executes LLM rewrite/edit when requested by Stage 2 and returns
 * model output/fallback details.
 */
internal class LlmStage(
    private val summaryEngine: SummaryEngine
) {
    fun processEdit(
        input: PreLlmResult.NeedsEditLlm,
        onShowRewriting: () -> Unit
    ): LlmStageResult {
        onShowRewriting()
        return when (
            val result = summaryEngine.applyEditInstructionBlocking(
                originalText = input.sourceText,
                instructionText = input.instruction
            )
        ) {
            is RewriteResult.Success -> LlmStageResult(
                invoked = true,
                output = result.text,
                backend = result.backend.name,
                llmOutputText = result.text
            )

            is RewriteResult.Failure -> LlmStageResult(
                invoked = true,
                output = input.sourceText,
                backend = result.backend?.name,
                errorType = result.error.type,
                errorMessage = result.error.litertError
            )
        }
    }
}

/**
 * Stage 4: applies final local rules after LLM output, then builds the
 * final rewrite result and diagnostics for commit/debug trace.
 */
internal class PostLlmRulesStage {
    fun processComplete(
        input: PreLlmResult.Complete
    ): ImeRewriteResult {
        return ImeRewriteResult(
            output = input.output,
            operation = input.operation,
            llmInvoked = false,
            applied = input.applied,
            backend = null,
            elapsedMs = 0L,
            editIntent = input.editIntent,
            diagnostics = input.diagnostics
        )
    }

    fun processEdit(
        input: PreLlmResult.NeedsEditLlm,
        llm: LlmStageResult
    ): ImeRewriteResult {
        val localRulesAfterLlm = mutableListOf<String>()
        val normalizedOutput = VoiceEngine.postReplaceCapitalization(
            sourceText = input.sourceText,
            instructionText = input.instruction,
            editedOutput = llm.output
        )
        if (normalizedOutput != llm.output) {
            localRulesAfterLlm += "post_replace_capitalization"
        }
        val diagnostics = ImeRewriteDiagnostics(
            localRulesBeforeLlm = input.diagnostics.localRulesBeforeLlm,
            llmOutputText = llm.llmOutputText,
            localRulesAfterLlm = localRulesAfterLlm
        )
        return ImeRewriteResult(
            output = normalizedOutput,
            operation = ImeOperation.EDIT,
            llmInvoked = llm.invoked,
            applied = normalizedOutput != input.sourceText,
            backend = llm.backend,
            errorType = llm.errorType,
            errorMessage = llm.errorMessage,
            elapsedMs = 0L,
            editIntent = input.editIntent,
            diagnostics = diagnostics
        )
    }
}

internal sealed interface PreLlmResult {
    val operation: ImeOperation
    val editIntent: String?
    val diagnostics: ImeRewriteDiagnostics

    data class Complete(
        override val operation: ImeOperation,
        val output: String,
        val applied: Boolean,
        override val editIntent: String?,
        override val diagnostics: ImeRewriteDiagnostics
    ) : PreLlmResult

    data class NeedsEditLlm(
        val sourceText: String,
        val instruction: String,
        override val editIntent: String,
        override val diagnostics: ImeRewriteDiagnostics
    ) : PreLlmResult {
        override val operation: ImeOperation = ImeOperation.EDIT
    }
}

internal data class LlmStageResult(
    val invoked: Boolean,
    val output: String,
    val backend: String?,
    val errorType: String? = null,
    val errorMessage: String? = null,
    val llmOutputText: String? = null
)
