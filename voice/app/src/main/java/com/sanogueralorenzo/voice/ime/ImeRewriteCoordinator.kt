package com.sanogueralorenzo.voice.ime

import android.os.SystemClock
import com.sanogueralorenzo.voice.summary.DeterministicComposeRewriter
import com.sanogueralorenzo.voice.summary.LiteRtComposeLlmGate
import com.sanogueralorenzo.voice.preferences.PreferencesRepository
import com.sanogueralorenzo.voice.summary.LiteRtEditHeuristics
import com.sanogueralorenzo.voice.summary.LiteRtSummarizer
import com.sanogueralorenzo.voice.summary.RewriteResult

internal class ImeRewriteCoordinator(
    private val preferencesRepository: PreferencesRepository,
    private val liteRtSummarizer: LiteRtSummarizer,
    private val deterministicComposeRewriter: DeterministicComposeRewriter,
    private val composeLlmGate: LiteRtComposeLlmGate
) {
    fun rewrite(
        sourceText: String,
        transcript: String,
        onShowRewriting: () -> Unit
    ): ImeRewriteResult {
        val normalizedTranscript = transcript.trim()
        val hasSource = sourceText.trim().isNotBlank()
        val shouldEdit = hasSource && LiteRtEditHeuristics.isStrictEditCommand(normalizedTranscript)

        return if (shouldEdit) {
            editCurrentTextWithInstruction(
                sourceText = sourceText,
                instructionTranscript = normalizedTranscript,
                onShowRewriting = onShowRewriting
            )
        } else {
            appendToSourceText(
                sourceText = sourceText,
                transcript = normalizedTranscript,
                onShowRewriting = onShowRewriting
            )
        }
    }

    private fun appendToSourceText(
        sourceText: String,
        transcript: String,
        onShowRewriting: () -> Unit
    ): ImeRewriteResult {
        val startedAt = SystemClock.uptimeMillis()
        if (sourceText.isBlank()) {
            val chunkResult = rewriteChunkIfNeeded(transcript, onShowRewriting)
            return ImeRewriteResult(
                output = chunkResult.output,
                operation = ImeOperation.APPEND,
                llmInvoked = chunkResult.llmInvoked,
                applied = chunkResult.output != transcript,
                backend = chunkResult.backend,
                errorType = chunkResult.errorType,
                errorMessage = chunkResult.errorMessage,
                elapsedMs = SystemClock.uptimeMillis() - startedAt,
                editIntent = null,
                diagnostics = chunkResult.diagnostics
            )
        }

        val chunkResult = rewriteChunkIfNeeded(transcript, onShowRewriting)
        val output = ImeAppendFormatter.append(sourceText = sourceText, chunkText = chunkResult.output)
        return ImeRewriteResult(
            output = output,
            operation = ImeOperation.APPEND,
            llmInvoked = chunkResult.llmInvoked,
            applied = output != sourceText,
            backend = chunkResult.backend,
            errorType = chunkResult.errorType,
            errorMessage = chunkResult.errorMessage,
            elapsedMs = SystemClock.uptimeMillis() - startedAt,
            editIntent = null,
            diagnostics = chunkResult.diagnostics
        )
    }

    private fun editCurrentTextWithInstruction(
        sourceText: String,
        instructionTranscript: String,
        onShowRewriting: () -> Unit
    ): ImeRewriteResult {
        val startedAt = SystemClock.uptimeMillis()
        val normalizedSource = sourceText.trim()
        val normalizedInstruction = instructionTranscript.trim()
        val localRulesBeforeLlm = mutableListOf("strict_edit_command")
        if (normalizedSource.isBlank() || normalizedInstruction.isBlank()) {
            return ImeRewriteResult(
                output = sourceText,
                operation = ImeOperation.EDIT,
                llmInvoked = false,
                applied = false,
                backend = null,
                elapsedMs = SystemClock.uptimeMillis() - startedAt,
                editIntent = null,
                diagnostics = ImeRewriteDiagnostics(localRulesBeforeLlm = localRulesBeforeLlm)
            )
        }
        val instructionAnalysis = LiteRtEditHeuristics.analyzeInstruction(normalizedInstruction)
        val editIntent = instructionAnalysis.intent.name

        val deterministicEdit = LiteRtEditHeuristics.tryApplyDeterministicEdit(
            sourceText = sourceText,
            instructionText = normalizedInstruction
        )
        if (deterministicEdit != null && !deterministicEdit.noMatchDetected) {
            localRulesBeforeLlm += "deterministic_${deterministicEdit.commandKind.name.lowercase()}"
            return ImeRewriteResult(
                output = deterministicEdit.output,
                operation = ImeOperation.EDIT,
                llmInvoked = false,
                applied = deterministicEdit.output != sourceText,
                backend = null,
                elapsedMs = SystemClock.uptimeMillis() - startedAt,
                editIntent = deterministicEdit.intent.name,
                diagnostics = ImeRewriteDiagnostics(localRulesBeforeLlm = localRulesBeforeLlm)
            )
        }
        if (deterministicEdit?.noMatchDetected == true) {
            localRulesBeforeLlm += "deterministic_no_match"
        }

        val rewriteEnabled = preferencesRepository.isLlmRewriteEnabled()
        if (!rewriteEnabled || !liteRtSummarizer.isModelAvailable()) {
            return ImeRewriteResult(
                output = sourceText,
                operation = ImeOperation.EDIT,
                llmInvoked = false,
                applied = false,
                backend = null,
                elapsedMs = SystemClock.uptimeMillis() - startedAt,
                editIntent = editIntent,
                diagnostics = ImeRewriteDiagnostics(localRulesBeforeLlm = localRulesBeforeLlm)
            )
        }

        onShowRewriting()
        val result = liteRtSummarizer.applyEditInstructionBlocking(
            originalText = sourceText,
            instructionText = normalizedInstruction
        )
        return when (result) {
            is RewriteResult.Success -> {
                val localRulesAfterLlm = mutableListOf<String>()
                val normalizedOutput = LiteRtEditHeuristics.applyPostReplaceCapitalization(
                    sourceText = sourceText,
                    instructionText = normalizedInstruction,
                    editedOutput = result.text
                )
                if (normalizedOutput != result.text) {
                    localRulesAfterLlm += "post_replace_capitalization"
                }
                ImeRewriteResult(
                    output = normalizedOutput,
                    operation = ImeOperation.EDIT,
                    llmInvoked = true,
                    applied = normalizedOutput != sourceText,
                    backend = result.backend.name,
                    elapsedMs = SystemClock.uptimeMillis() - startedAt,
                    editIntent = editIntent,
                    diagnostics = ImeRewriteDiagnostics(
                        localRulesBeforeLlm = localRulesBeforeLlm,
                        llmOutputText = result.text,
                        localRulesAfterLlm = localRulesAfterLlm
                    )
                )
            }

            is RewriteResult.Failure -> ImeRewriteResult(
                output = sourceText,
                operation = ImeOperation.EDIT,
                llmInvoked = true,
                applied = false,
                backend = result.backend?.name,
                errorType = result.error.type,
                errorMessage = result.error.litertError,
                elapsedMs = SystemClock.uptimeMillis() - startedAt,
                editIntent = editIntent,
                diagnostics = ImeRewriteDiagnostics(localRulesBeforeLlm = localRulesBeforeLlm)
            )
        }
    }

    private fun rewriteChunkIfNeeded(
        transcript: String,
        onShowRewriting: () -> Unit
    ): ChunkRewriteResult {
        val deterministicResult = deterministicComposeRewriter.rewrite(transcript)
        val localRulesBeforeLlm = deterministicResult.appliedRules.map { rule ->
            "compose_${rule.name.lowercase()}"
        }
        val llmCandidate = composeLlmGate.shouldUseLlm(
            originalText = transcript,
            deterministicResult = deterministicResult
        )
        val rewriteEnabled = preferencesRepository.isLlmRewriteEnabled()
        val shouldRewrite = rewriteEnabled && transcript.isNotBlank() && liteRtSummarizer.isModelAvailable()
        if (!shouldRewrite) {
            return ChunkRewriteResult(
                output = transcript,
                llmInvoked = false,
                backend = null,
                diagnostics = ImeRewriteDiagnostics(localRulesBeforeLlm = localRulesBeforeLlm)
            )
        }

        onShowRewriting()
        return when (val result = liteRtSummarizer.summarizeBlocking(text = transcript)) {
            is RewriteResult.Success -> ChunkRewriteResult(
                output = result.text,
                llmInvoked = llmCandidate,
                backend = result.backend.name,
                diagnostics = ImeRewriteDiagnostics(
                    localRulesBeforeLlm = localRulesBeforeLlm,
                    llmOutputText = if (llmCandidate) result.text else null,
                    localRulesAfterLlm = if (llmCandidate && result.text != deterministicResult.text) {
                        listOf("compose_output_policy")
                    } else {
                        emptyList()
                    }
                )
            )

            is RewriteResult.Failure -> ChunkRewriteResult(
                output = transcript,
                llmInvoked = llmCandidate,
                backend = result.backend?.name,
                errorType = result.error.type,
                errorMessage = result.error.litertError,
                diagnostics = ImeRewriteDiagnostics(localRulesBeforeLlm = localRulesBeforeLlm)
            )
        }
    }

    private data class ChunkRewriteResult(
        val output: String,
        val llmInvoked: Boolean,
        val backend: String?,
        val errorType: String? = null,
        val errorMessage: String? = null,
        val diagnostics: ImeRewriteDiagnostics = ImeRewriteDiagnostics()
    )
}
