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
        mode: ImeSendMode,
        transcript: String,
        editSourceText: String,
        onShowRewriting: () -> Unit
    ): ImeRewriteResult {
        return if (mode == ImeSendMode.EDIT_EXISTING) {
            editCurrentTextWithInstruction(
                sourceText = editSourceText,
                instructionTranscript = transcript,
                onShowRewriting = onShowRewriting
            )
        } else {
            rewriteTranscriptIfNeeded(
                transcript = transcript,
                onShowRewriting = onShowRewriting
            )
        }
    }

    private fun rewriteTranscriptIfNeeded(
        transcript: String,
        onShowRewriting: () -> Unit
    ): ImeRewriteResult {
        val startedAt = SystemClock.uptimeMillis()
        val rewriteEnabled = settingsStore.isLiteRtRewriteEnabled()
        val shouldRewrite = rewriteEnabled && transcript.isNotBlank() && liteRtSummarizer.isModelAvailable()
        if (shouldRewrite) {
            onShowRewriting()
        }
        if (!shouldRewrite) {
            return ImeRewriteResult(
                output = transcript,
                attempted = false,
                applied = false,
                backend = null,
                elapsedMs = SystemClock.uptimeMillis() - startedAt,
                editIntent = null
            )
        }

        val result = liteRtSummarizer.summarizeBlocking(text = transcript)
        return when (result) {
            is RewriteResult.Success -> ImeRewriteResult(
                output = result.text,
                attempted = true,
                applied = result.text != transcript,
                backend = result.backend.name,
                elapsedMs = SystemClock.uptimeMillis() - startedAt,
                editIntent = null
            )

            is RewriteResult.Failure -> ImeRewriteResult(
                output = transcript,
                attempted = true,
                applied = false,
                backend = result.backend?.name,
                errorType = result.error.type,
                errorMessage = result.error.litertError,
                elapsedMs = SystemClock.uptimeMillis() - startedAt,
                editIntent = null
            )
        }
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
                attempted = false,
                applied = deterministicEdit.output != sourceText,
                backend = null,
                elapsedMs = SystemClock.uptimeMillis() - startedAt,
                editIntent = deterministicEdit.intent.name
            )
        }

        val rewriteEnabled = settingsStore.isLiteRtRewriteEnabled()
        if (!rewriteEnabled) {
            return ImeRewriteResult(
                output = sourceText,
                attempted = false,
                applied = false,
                backend = null,
                elapsedMs = SystemClock.uptimeMillis() - startedAt,
                editIntent = editIntent
            )
        }
        if (!liteRtSummarizer.isModelAvailable()) {
            return ImeRewriteResult(
                output = sourceText,
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
            is RewriteResult.Success -> ImeRewriteResult(
                output = result.text,
                attempted = true,
                applied = result.text != sourceText,
                backend = result.backend.name,
                elapsedMs = SystemClock.uptimeMillis() - startedAt,
                editIntent = editIntent
            )

            is RewriteResult.Failure -> ImeRewriteResult(
                output = sourceText,
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
}
