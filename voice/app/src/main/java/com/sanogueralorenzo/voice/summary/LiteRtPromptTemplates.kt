package com.sanogueralorenzo.voice.summary

/**
 * Centralized prompt templates for LiteRT rewrite/edit operations.
 */
internal object LiteRtPromptTemplates {
    fun buildRewriteSystemInstruction(
        bulletMode: Boolean,
        customInstructions: String
    ): String {
        val formatRule = if (bulletMode) {
            "Preserve existing list formatting and list order exactly."
        } else {
            "Do not convert prose into bullets or change line structure."
        }
        val customRule = customInstructionsRule(customInstructions)
        return "$BASE_REWRITE_INSTRUCTION $formatRule $REWRITE_SAFETY_INSTRUCTION $customRule"
    }

    fun buildEditSystemInstruction(customInstructions: String): String {
        val customRule = customInstructionsRule(customInstructions)
        return "$EDIT_SYSTEM_INSTRUCTION $customRule"
    }

    fun benchmarkInstructionSnapshot(customInstructions: String): String {
        val normalizedCustom = customInstructions.trim()
        val customDisplay = if (normalizedCustom.isBlank()) "none" else normalizedCustom
        val rewriteInstruction = buildRewriteSystemInstruction(
            bulletMode = false,
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

    private const val BASE_REWRITE_INSTRUCTION =
        "Clean dictated text with strict minimal edits: remove only spoken disfluencies and " +
            "filler tokens such as um, uh, erm, emm, and hmm, including repeated filler runs."

    private const val REWRITE_SAFETY_INSTRUCTION =
        "Do not paraphrase, summarize, reorder, add, or remove any other content. " +
            "Preserve names, numbers, dates, links, negation, constraints, wording, and tone. " +
            "If uncertain, return the text unchanged. Output only the cleaned text."

    private const val EDIT_SYSTEM_INSTRUCTION =
        "Apply only the explicit EDIT_INSTRUCTION to ORIGINAL_MESSAGE. " +
            "Allowed operations are: delete target text (or delete-all), replace X with Y, and " +
            "add/insert requested text. " +
            "Keep untouched content exactly as-is with no paraphrasing, tone changes, or extra cleanup. " +
            "If instruction contains correction turns ('X no, Y'), apply final correction Y. " +
            "When PREFER_LIST_FORMAT is yes, preserve list formatting. " +
            "If instruction is ambiguous, return ORIGINAL_MESSAGE unchanged. " +
            "Return only the final edited message."

    private fun customInstructionsRule(customInstructions: String): String {
        val trimmed = customInstructions.trim()
        if (trimmed.isBlank()) return ""
        return "Secondary user preference (only if it does not conflict with rules above): $trimmed"
    }
}
