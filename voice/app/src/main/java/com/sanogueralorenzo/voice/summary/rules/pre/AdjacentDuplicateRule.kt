package com.sanogueralorenzo.voice.summary.rules.pre

internal class AdjacentDuplicateRule : PreLlmRule {
    override fun apply(text: String): String {
        var current = text
        while (true) {
            val replaced = ADJACENT_DUPLICATE_REGEX.replace(current) { match ->
                match.groupValues[1]
            }
            if (replaced == current) return replaced
            current = replaced
        }
    }

    private companion object {
        private val ADJACENT_DUPLICATE_REGEX = Regex(
            "(?i)\\b([\\p{L}\\p{N}']+)\\b(?:\\s+\\1\\b)+"
        )
    }
}
