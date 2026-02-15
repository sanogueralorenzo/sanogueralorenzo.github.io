package com.sanogueralorenzo.voice.summary

/**
 * Centralized prompt templates for LiteRT rewrite/edit operations.
 */
internal object LiteRtPromptTemplates {
    enum class RewriteDirective {
        DEFAULT,
        SHORT,
        WARM,
        WORK
    }

    fun buildRewriteSystemInstruction(
        directive: RewriteDirective,
        bulletMode: Boolean,
        allowStrongTransform: Boolean,
        customInstructions: String
    ): String {
        val directiveRule = when (directive) {
            RewriteDirective.DEFAULT ->
                "Keep neutral tone and preserve the speaker's wording as much as possible."

            RewriteDirective.SHORT ->
                "Make only a light trim (about 5-15%). Keep original wording, structure, and all details."

            RewriteDirective.WARM ->
                "Make tone slightly warmer while keeping original wording and structure as much as possible."

            RewriteDirective.WORK ->
                "Make tone slightly more professional while keeping original wording and structure as much as possible."
        }
        val formatRule = if (bulletMode) {
            "If source is already list-like, preserve list structure; otherwise use '- ' bullets only when content is naturally list-like."
        } else {
            "Output plain prose with punctuation and capitalization. Do not force bullets for normal prose."
        }
        val intensityRule = if (allowStrongTransform) {
            "The speaker requested high-intensity rewriting. You may apply stronger tone/conciseness changes but still keep all facts and intent."
        } else {
            "If speaker guidelines appear at the beginning, follow them conservatively by default. Only make light edits unless intensity is explicitly strong."
        }
        val customRule = customInstructionsRule(customInstructions)
        return "$BASE_REWRITE_INSTRUCTIONS $directiveRule $intensityRule $formatRule $REWRITE_SAFETY_INSTRUCTIONS $customRule"
    }

    fun buildEditSystemInstruction(customInstructions: String): String {
        val customRule = customInstructionsRule(customInstructions)
        return "$EDIT_SYSTEM_INSTRUCTION $customRule"
    }

    fun buildEditUserPrompt(
        originalText: String,
        instructionText: String,
        editIntent: String,
        listMode: Boolean
    ): String {
        return buildString(originalText.length + instructionText.length + 180) {
            append("EDIT_INTENT: ")
            append(editIntent)
            append('\n')
            append("PREFER_LIST_FORMAT: ")
            append(if (listMode) "yes" else "no")
            append("\n\n")
            append("ORIGINAL_MESSAGE:\n")
            append(originalText)
            append("\n\nEDIT_INSTRUCTION:\n")
            append(instructionText)
        }
    }

    const val PROBE_SYSTEM_INSTRUCTION: String =
        "Reply with exactly OK. No markdown, no punctuation, no extra words."
    const val PROBE_USER_MESSAGE: String = "Reply with OK."

    private const val BASE_REWRITE_INSTRUCTIONS =
        "You rewrite noisy ASR transcripts into send-ready text with minimal edits. " +
            "Remove filler/repeats, keep final intent, and fix only unambiguous ASR mistakes. " +
            "If uncertain, preserve the original wording."
    private const val REWRITE_SAFETY_INSTRUCTIONS =
        "Do not summarize and do not add context. " +
            "Preserve names, numbers, dates, links, negation, and key constraints exactly. " +
            "Do not add social filler or invented actions. " +
            "Output only the rewritten text."
    private const val EDIT_SYSTEM_INSTRUCTION =
        "Apply EDIT_INSTRUCTION to ORIGINAL_MESSAGE exactly. " +
            "If EDIT_INTENT indicates delete-all, return an empty final message. " +
            "If instruction includes correction turns ('X no, Y'), apply the final correction Y. " +
            "When PREFER_LIST_FORMAT is yes and content is list-like, keep clean '- ' bullets. " +
            "Keep untouched content faithful. Do not invent facts or add social filler. " +
            "Return only the fully edited final message, with no explanations."

    private fun customInstructionsRule(customInstructions: String): String {
        val trimmed = customInstructions.trim()
        if (trimmed.isBlank()) return ""
        return "Additional user rewrite preference: $trimmed"
    }
}
