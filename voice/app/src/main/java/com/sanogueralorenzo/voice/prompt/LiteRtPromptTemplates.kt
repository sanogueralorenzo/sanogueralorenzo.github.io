package com.sanogueralorenzo.voice.prompt

/**
 * Centralized prompt templates for LiteRT rewrite/edit operations.
 */
internal object LiteRtPromptTemplates {
    fun buildRewriteSystemInstruction(rewriteInstructionOverride: String? = null): String {
        val raw = rewriteInstructionOverride
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?: REWRITE_SYSTEM_INSTRUCTION
        return normalizeRewriteSystemInstruction(raw)
    }

    fun buildEditSystemInstruction(): String {
        return EDIT_SYSTEM_INSTRUCTION
    }

    fun buildRewriteUserPrompt(
        inputText: String
    ): String {
        return inputText
    }

    fun benchmarkInstructionSnapshot(
        rewriteInstructionOverride: String? = null
    ): String {
        val rewriteInstruction = buildRewriteSystemInstruction(rewriteInstructionOverride)
        val editInstruction = buildEditSystemInstruction()
        return buildString {
            appendLine("rewrite_system_instruction:")
            appendLine(rewriteInstruction)
            appendLine()
            appendLine("edit_system_instruction:")
            appendLine(editInstruction)
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

    private val REWRITE_SYSTEM_INSTRUCTION =
        """
        Clean this dictated message with minimal edits.
        Allowed edits: remove spoken fillers, remove immediate duplicate words, fix obvious transcription mistakes, and normalize min/mins to minutes.
        If input has digits, keep digits in output.
        If input has numbers written in words, always convert them to digits.
        Do not paraphrase, summarize, reorder, or change meaning, tone, person, or intent.
        If no allowed edit applies, return input unchanged.
        If uncertain, return input unchanged.
        Return only the cleaned message, with no prefix or explanation.
        """.trimIndent()
    private const val EDIT_SYSTEM_INSTRUCTION =
        "Apply EDIT_INSTRUCTION to ORIGINAL_MESSAGE exactly. " +
            "If EDIT_INTENT indicates delete-all, return an empty final message. " +
            "If instruction includes correction turns ('X no, Y'), apply the final correction Y. " +
            "When PREFER_LIST_FORMAT is yes and content is list-like, keep clean '- ' bullets. " +
            "Keep untouched content faithful. Do not invent facts or add social filler. " +
            "Return only the fully edited final message, with no explanations."

    private fun normalizeRewriteSystemInstruction(raw: String): String {
        val withoutUserBlock = raw.substringBefore("\n\nUser input:").trim()
        val withoutPlaceholders = withoutUserBlock
            .replace("{{input}}", "")
            .replace("{input}", "")
            .replace("\n\nCleaned:", "")
        return withoutPlaceholders.trim()
    }
}
