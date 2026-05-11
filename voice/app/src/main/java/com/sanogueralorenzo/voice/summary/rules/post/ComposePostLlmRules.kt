package com.sanogueralorenzo.voice.summary.rules.post

/**
 * Deterministic compose normalization and guardrails around model output.
 *
 * Possible outcomes:
 * - Input normalization returns cleaned text or `""`.
 * - Output cleanup returns cleaned text or `""` when model output is unusable.
 * - Finalization returns candidate output or falls back to original input when
 *   safety/quality checks fail.
 */
class ComposePostLlmRules {
    private val composeInputCleanupRule = ComposeInputCleanupRule()
    private val instructionInputCleanupRule = InstructionInputCleanupRule()
    private val modelOutputCleanupRule = ModelOutputCleanupRule()
    private val sentenceCapitalizationRule = SentenceCapitalizationRule()
    private val spokenNumberOutputRule = SpokenNumberOutputRule()
    private val outputGuardrailRule = ComposeOutputGuardrailRule()

    fun normalizeComposeInput(text: String): String {
        return composeInputCleanupRule.apply(text)
    }

    fun normalizeInstructionInput(text: String): String {
        return instructionInputCleanupRule.apply(text)
    }

    fun cleanModelOutput(
        text: String,
        bulletMode: Boolean
    ): String {
        val cleaned = modelOutputCleanupRule.clean(text = text, bulletMode = bulletMode)
        if (cleaned.isBlank()) return ""
        return normalizeComposeOutputText(cleaned)
    }

    fun normalizeComposeOutputText(text: String): String {
        val trimmed = text.trim()
        if (trimmed.isBlank()) return ""
        return spokenNumberOutputRule.apply(sentenceCapitalizationRule.apply(trimmed))
    }

    fun finalizeComposeOutput(
        originalText: String,
        modelOutput: String,
        listMode: Boolean
    ): String {
        val original = originalText.trim()
        val candidate = cleanModelOutput(modelOutput, bulletMode = listMode).trim()
        return outputGuardrailRule.choose(original = original, candidate = candidate)
    }
}
