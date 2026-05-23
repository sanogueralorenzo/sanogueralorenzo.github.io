package com.sanogueralorenzo.voice.summary.rules.post

internal class InstructionInputCleanupRule {
    fun apply(text: String): String {
        return text.replace(WHITESPACE_REGEX, " ").trim()
    }

    private companion object {
        private val WHITESPACE_REGEX = Regex("\\s+")
    }
}
