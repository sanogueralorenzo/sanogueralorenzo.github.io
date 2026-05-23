package com.sanogueralorenzo.voice.summary.rules.post

internal class ComposeInputCleanupRule {
    fun apply(text: String): String {
        val collapsed = text.replace(WHITESPACE_REGEX, " ").trim()
        if (collapsed.isBlank()) return ""
        return collapsed
            .replace(REPEATED_FILLER_REGEX, "$1")
            .replace(SPACE_BEFORE_PUNCTUATION_REGEX, "$1")
            .replace(REPEATED_PUNCTUATION_REGEX, "$1")
            .trim()
    }

    private companion object {
        private val WHITESPACE_REGEX = Regex("\\s+")
        private val REPEATED_FILLER_REGEX = Regex(
            "\\b(um+|uh+|erm+|emm+|hmm+)(?:\\s+\\1\\b)+",
            RegexOption.IGNORE_CASE
        )
        private val SPACE_BEFORE_PUNCTUATION_REGEX = Regex("\\s+([,.;!?])")
        private val REPEATED_PUNCTUATION_REGEX = Regex("([,.;!?])\\1+")
    }
}
