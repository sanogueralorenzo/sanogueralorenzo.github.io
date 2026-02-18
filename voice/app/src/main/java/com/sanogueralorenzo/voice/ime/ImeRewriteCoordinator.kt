package com.sanogueralorenzo.voice.ime

import android.os.SystemClock
import com.sanogueralorenzo.voice.settings.VoiceSettingsStore
import com.sanogueralorenzo.voice.summary.LiteRtEditHeuristics
import com.sanogueralorenzo.voice.summary.LiteRtSummarizer
import com.sanogueralorenzo.voice.summary.RewriteResult

internal class ImeRewriteCoordinator(
    private val settingsStore: VoiceSettingsStore,
    private val liteRtSummarizer: LiteRtSummarizer
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
                attempted = chunkResult.attempted,
                applied = chunkResult.output != transcript,
                backend = chunkResult.backend,
                errorType = chunkResult.errorType,
                errorMessage = chunkResult.errorMessage,
                elapsedMs = SystemClock.uptimeMillis() - startedAt,
                editIntent = null
            )
        }

        val chunkResult = rewriteChunkIfNeeded(transcript, onShowRewriting)
        val output = ImeAppendFormatter.append(sourceText = sourceText, chunkText = chunkResult.output)
        return ImeRewriteResult(
            output = output,
            operation = ImeOperation.APPEND,
            attempted = chunkResult.attempted,
            applied = output != sourceText,
            backend = chunkResult.backend,
            errorType = chunkResult.errorType,
            errorMessage = chunkResult.errorMessage,
            elapsedMs = SystemClock.uptimeMillis() - startedAt,
            editIntent = null
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
        if (normalizedSource.isBlank() || normalizedInstruction.isBlank()) {
            return ImeRewriteResult(
                output = sourceText,
                operation = ImeOperation.EDIT,
                attempted = false,
                applied = false,
                backend = null,
                elapsedMs = SystemClock.uptimeMillis() - startedAt,
                editIntent = null
            )
        }
        val instructionAnalysis = LiteRtEditHeuristics.analyzeInstruction(normalizedInstruction)
        val editIntent = instructionAnalysis.intent.name

        val deterministicEdit = LiteRtEditHeuristics.tryApplyDeterministicEdit(
            sourceText = sourceText,
            instructionText = normalizedInstruction
        )
        if (deterministicEdit != null && !deterministicEdit.noMatchDetected) {
            return ImeRewriteResult(
                output = deterministicEdit.output,
                operation = ImeOperation.EDIT,
                attempted = false,
                applied = deterministicEdit.output != sourceText,
                backend = null,
                elapsedMs = SystemClock.uptimeMillis() - startedAt,
                editIntent = deterministicEdit.intent.name
            )
        }

        val rewriteEnabled = settingsStore.isLiteRtRewriteEnabled()
        if (!rewriteEnabled || !liteRtSummarizer.isModelAvailable()) {
            return ImeRewriteResult(
                output = sourceText,
                operation = ImeOperation.EDIT,
                attempted = false,
                applied = false,
                backend = null,
                elapsedMs = SystemClock.uptimeMillis() - startedAt,
                editIntent = editIntent
            )
        }

        onShowRewriting()
        val result = liteRtSummarizer.applyEditInstructionBlocking(
            originalText = sourceText,
            instructionText = normalizedInstruction
        )
        return when (result) {
            is RewriteResult.Success -> {
                val normalizedOutput = LiteRtEditHeuristics.applyPostReplaceCapitalization(
                    sourceText = sourceText,
                    instructionText = normalizedInstruction,
                    editedOutput = result.text
                )
                ImeRewriteResult(
                    output = normalizedOutput,
                    operation = ImeOperation.EDIT,
                    attempted = true,
                    applied = normalizedOutput != sourceText,
                    backend = result.backend.name,
                    elapsedMs = SystemClock.uptimeMillis() - startedAt,
                    editIntent = editIntent
                )
            }

            is RewriteResult.Failure -> ImeRewriteResult(
                output = sourceText,
                operation = ImeOperation.EDIT,
                attempted = true,
                applied = false,
                backend = result.backend?.name,
                errorType = result.error.type,
                errorMessage = result.error.litertError,
                elapsedMs = SystemClock.uptimeMillis() - startedAt,
                editIntent = editIntent
            )
        }
    }

    private fun rewriteChunkIfNeeded(
        transcript: String,
        onShowRewriting: () -> Unit
    ): ChunkRewriteResult {
        val rewriteEnabled = settingsStore.isLiteRtRewriteEnabled()
        val shouldRewrite = rewriteEnabled && transcript.isNotBlank() && liteRtSummarizer.isModelAvailable()
        if (!shouldRewrite) {
            return ChunkRewriteResult(
                output = transcript,
                attempted = false,
                backend = null
            )
        }

        onShowRewriting()
        return when (val result = liteRtSummarizer.summarizeBlocking(text = transcript)) {
            is RewriteResult.Success -> ChunkRewriteResult(
                output = result.text,
                attempted = true,
                backend = result.backend.name
            )

            is RewriteResult.Failure -> ChunkRewriteResult(
                output = transcript,
                attempted = true,
                backend = result.backend?.name,
                errorType = result.error.type,
                errorMessage = result.error.litertError
            )
        }
    }

    private data class ChunkRewriteResult(
        val output: String,
        val attempted: Boolean,
        val backend: String?,
        val errorType: String? = null,
        val errorMessage: String? = null
    )
}
