package com.sanogueralorenzo.voice.ime

import com.sanogueralorenzo.voice.summary.EditInstructionRules

internal object ImeAppendFormatter {
    fun append(sourceText: String, chunkText: String): String {
        val source = sourceText.trimEnd()
        val chunk = chunkText.trim()
        if (chunk.isBlank()) return sourceText
        if (source.isBlank()) return chunk

        val useNewline = EditInstructionRules.looksLikeList(source) ||
            EditInstructionRules.looksLikeList(chunk)
        val separator = if (useNewline) "\n" else " "
        val joined = source + separator + chunk
        return joined
            .replace(SpaceBeforePunctuationRegex, "$1")
            .replace(MultiSpaceRegex, " ")
            .replace(SpacedNewlineRegex, "\n")
            .replace(MultiNewlineRegex, "\n\n")
            .trim()
    }

    private val SpaceBeforePunctuationRegex = Regex("\\s+([,.;:!?])")
    private val MultiSpaceRegex = Regex(" {2,}")
    private val SpacedNewlineRegex = Regex("[ \\t]*\\n[ \\t]*")
    private val MultiNewlineRegex = Regex("\\n{3,}")
}
