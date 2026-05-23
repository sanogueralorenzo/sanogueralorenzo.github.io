package com.sanogueralorenzo.voice.summary.rules.post

internal class SentenceCapitalizationRule {
    fun apply(text: String): String {
        if (text.isBlank()) return text
        val chars = text.toCharArray()
        var uppercaseNextLetter = true
        for (i in chars.indices) {
            val current = chars[i]
            if (uppercaseNextLetter && current.isLetter()) {
                chars[i] = current.uppercaseChar()
                uppercaseNextLetter = false
            }
            if (current.isLetterOrDigit()) {
                uppercaseNextLetter = false
            }
            if (isSentenceBoundary(chars = chars, index = i)) {
                uppercaseNextLetter = true
            }
        }
        val sentenceCased = String(chars)
        val withStandaloneI = STANDALONE_I_REGEX.replace(sentenceCased, "I")
        return I_CONTRACTION_REGEX.replace(withStandaloneI) { match ->
            "I'${match.groupValues[1].lowercase()}"
        }
    }

    private fun isSentenceBoundary(
        chars: CharArray,
        index: Int
    ): Boolean {
        val current = chars[index]
        if (current == '\n') return true
        if (current == '!' || current == '?') return true
        if (current != '.') return false

        val prev = chars.getOrNull(index - 1)
        val next = chars.getOrNull(index + 1)
        if (prev != null && prev.isDigit() && next != null && next.isDigit()) {
            return false
        }
        return next == null || next.isWhitespace()
    }

    private companion object {
        private val STANDALONE_I_REGEX = Regex("(?i)\\bi\\b")
        private val I_CONTRACTION_REGEX = Regex("(?i)\\bi'([a-z]+)\\b")
    }
}
