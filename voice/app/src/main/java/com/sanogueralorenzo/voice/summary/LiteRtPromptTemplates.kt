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
        val customRule = customInstructionsRule(customInstructions)
        return if (customRule.isBlank()) {
            REWRITE_SYSTEM_INSTRUCTION
        } else {
            "$REWRITE_SYSTEM_INSTRUCTION $customRule"
        }
    }

    fun buildEditSystemInstruction(customInstructions: String): String {
        val customRule = customInstructionsRule(customInstructions)
        return "$EDIT_SYSTEM_INSTRUCTION $customRule"
    }

    fun benchmarkInstructionSnapshot(customInstructions: String): String {
        val normalizedCustom = customInstructions.trim()
        val customDisplay = if (normalizedCustom.isBlank()) "none" else normalizedCustom
        val rewriteInstruction = buildRewriteSystemInstruction(
            directive = RewriteDirective.DEFAULT,
            bulletMode = false,
            allowStrongTransform = false,
            customInstructions = customInstructions
        )
        val editInstruction = buildEditSystemInstruction(customInstructions)
        return buildString {
            appendLine("rewrite_system_instruction:")
            appendLine(rewriteInstruction)
            appendLine()
            appendLine("edit_system_instruction:")
            appendLine(editInstruction)
            appendLine()
            appendLine("custom_instructions:")
            append(customDisplay)
        }
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

    private const val REWRITE_SYSTEM_INSTRUCTION =
        "Clean this dictated message with minimal edits. " +
            "Allowed edits: remove spoken fillers, remove immediate duplicate words, " +
            "fix obvious transcription mistakes, and normalize min/mins to minutes. " +
            "If input has digits, keep digits in output. " +
            "If input has numbers written in words, always convert them to digits. " +
            "Do not paraphrase, summarize, reorder, or change meaning, tone, person, or intent. " +
            "If no allowed edit applies, return input unchanged. " +
            "If uncertain, return input unchanged. " +
            "Return only the cleaned message after the label \"Cleaned:\"."
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
