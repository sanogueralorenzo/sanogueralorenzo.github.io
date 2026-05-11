package com.sanogueralorenzo.voice.summary.rules.pre

internal class SurfaceCleanupRule : PreLlmRule {
    override fun apply(text: String): String {
        return text
            .replace(SPACE_BEFORE_PUNCTUATION_REGEX, "$1")
            .replace(DUPLICATE_COMMA_REGEX, ",")
            .replace(ORPHAN_COMMA_REGEX, "")
            .replace(MULTI_SPACE_REGEX, " ")
            .trim()
    }

    private companion object {
        private val MULTI_SPACE_REGEX = Regex(" {2,}")
        private val SPACE_BEFORE_PUNCTUATION_REGEX = Regex("\\s+([,.;!?])")
        private val DUPLICATE_COMMA_REGEX = Regex(",\\s*,+")
        private val ORPHAN_COMMA_REGEX = Regex(",\\s*(?=[.!?]|$)")
    }
}
