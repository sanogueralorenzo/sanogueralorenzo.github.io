package com.sanogueralorenzo.voice.summary.rules.post

import com.sanogueralorenzo.voice.engine.VoiceEngine

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
    fun normalizeComposeInput(text: String): String {
        return VoiceEngine.normalizeComposeInput(text)
    }

    fun normalizeInstructionInput(text: String): String {
        return VoiceEngine.normalizeInstructionInput(text)
    }

    fun cleanModelOutput(
        text: String,
        bulletMode: Boolean
    ): String {
        return VoiceEngine.cleanModelOutput(
            text = text,
            bulletMode = bulletMode
        )
    }

    fun normalizeComposeOutputText(text: String): String {
        return VoiceEngine.normalizeComposeOutputText(text)
    }

    fun finalizeComposeOutput(
        originalText: String,
        modelOutput: String,
        listMode: Boolean
    ): String {
        return VoiceEngine.postprocess(
            originalText = originalText,
            modelOutput = modelOutput,
            listMode = listMode
        )
    }
}
