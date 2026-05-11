package com.sanogueralorenzo.voice.summary.rules.pre

internal class CorrectionTurnRule : PreLlmRule {
    override fun apply(text: String): String {
        var current = text
        var passChanged: Boolean
        do {
            passChanged = false
            val prepositionResolved = PREPOSITION_CORRECTION_REGEX.replace(current) { match ->
                val preposition = match.groupValues[1]
                val replacement = match.groupValues[3]
                val resolved = "$preposition $replacement"
                if (resolved != match.value) {
                    passChanged = true
                }
                resolved
            }
            current = prepositionResolved

            val genericResolved = GENERIC_CORRECTION_REGEX.replace(current) { match ->
                val oldValue = match.groupValues[1]
                val replacement = match.groupValues[2]
                if (!isLikelyCorrectionValue(oldValue = oldValue, replacement = replacement)) {
                    return@replace match.value
                }
                if (replacement != match.value) {
                    passChanged = true
                }
                replacement
            }
            current = genericResolved
        } while (passChanged)
        return current
    }

    private fun isLikelyCorrectionValue(
        oldValue: String,
        replacement: String
    ): Boolean {
        if (oldValue.equals(replacement, ignoreCase = true)) return false
        val oldTrimmed = oldValue.trim()
        val replacementTrimmed = replacement.trim()
        if (oldTrimmed.isBlank() || replacementTrimmed.isBlank()) return false
        if (oldTrimmed.length > 36 || replacementTrimmed.length > 36) return false
        if (DIGIT_REGEX.containsMatchIn(oldTrimmed) || DIGIT_REGEX.containsMatchIn(replacementTrimmed)) return true
        if (containsCardinalWord(oldTrimmed) || containsCardinalWord(replacementTrimmed)) return true
        return oldTrimmed.split(WHITESPACE_REGEX).size <= 2 &&
            replacementTrimmed.split(WHITESPACE_REGEX).size <= 2
    }

    private fun containsCardinalWord(text: String): Boolean {
        val tokens = text
            .lowercase()
            .replace('-', ' ')
            .split(WHITESPACE_REGEX)
            .filter { it.isNotBlank() }
        return tokens.any { token -> token in ALL_NUMBER_WORDS }
    }

    private companion object {
        private val WHITESPACE_REGEX = Regex("\\s+")
        private val DIGIT_REGEX = Regex("\\d")
        private val PREPOSITION_CORRECTION_REGEX = Regex(
            "(?i)\\b(to|at|on|for|in|after|before|around|about)\\s+" +
                "([\\p{L}\\p{N}:.'-]+(?:\\s+[\\p{L}\\p{N}:.'-]+){0,3})\\s*" +
                "(?:,\\s*)?(?:no|actually|sorry|rather|instead|i\\s+mean)\\s+" +
                "(?:\\1\\s+)?([\\p{L}\\p{N}:.'-]+(?:\\s+[\\p{L}\\p{N}:.'-]+){0,3})"
        )
        private val GENERIC_CORRECTION_REGEX = Regex(
            "(?i)\\b([\\p{L}\\p{N}:.'-]+(?:\\s+[\\p{L}\\p{N}:.'-]+){0,2})\\s*" +
                "(?:,\\s*)?(?:no|actually|sorry|rather|instead|i\\s+mean)\\s+" +
                "([\\p{L}\\p{N}:.'-]+(?:\\s+[\\p{L}\\p{N}:.'-]+){0,2})(?=\\s*(?:[.!?,;:]|$))"
        )
        private val ALL_NUMBER_WORDS = NumberWordsToDigitsRule.ALL_NUMBER_WORDS
    }
}
