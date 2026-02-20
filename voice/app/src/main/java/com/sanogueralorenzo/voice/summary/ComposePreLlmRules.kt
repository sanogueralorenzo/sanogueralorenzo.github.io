package com.sanogueralorenzo.voice.summary

/**
 * Local deterministic rewrite pass for compose flow.
 * Applies safe, narrow transformations before any LLM call.
 */
class ComposePreLlmRules {
    data class Result(
        val text: String,
        val changed: Boolean,
        val appliedRules: Set<Rule>
    )

    enum class Rule {
        FILLER,
        ADJACENT_DUPLICATE,
        MINUTES_NORMALIZATION,
        NUMBER_WORDS_TO_DIGITS,
        CORRECTION_TURN
    }

    fun rewrite(input: String): Result {
        val source = input.trim()
        if (source.isBlank()) {
            return Result(text = "", changed = false, appliedRules = emptySet())
        }

        var current = source
        val applied = linkedSetOf<Rule>()

        val noFillers = removeStandaloneFillers(current)
        if (noFillers != current) {
            applied += Rule.FILLER
            current = noFillers
        }

        val noAdjacentDuplicates = removeAdjacentDuplicateWords(current)
        if (noAdjacentDuplicates != current) {
            applied += Rule.ADJACENT_DUPLICATE
            current = noAdjacentDuplicates
        }

        val normalizedMinutes = normalizeMinutesTokens(current)
        if (normalizedMinutes != current) {
            applied += Rule.MINUTES_NORMALIZATION
            current = normalizedMinutes
        }

        val resolvedCorrections = resolveCorrectionTurns(current)
        if (resolvedCorrections != current) {
            applied += Rule.CORRECTION_TURN
            current = resolvedCorrections
        }

        val normalizedNumbers = normalizeNumberWordsToDigits(current)
        if (normalizedNumbers != current) {
            applied += Rule.NUMBER_WORDS_TO_DIGITS
            current = normalizedNumbers
        }

        val finalText = normalizeSurface(current)
        return Result(
            text = finalText,
            changed = finalText != source,
            appliedRules = applied
        )
    }

    private fun removeStandaloneFillers(text: String): String {
        return FILLER_TOKEN_REGEX.replace(text, " ")
    }

    private fun removeAdjacentDuplicateWords(text: String): String {
        var current = text
        while (true) {
            val replaced = ADJACENT_DUPLICATE_REGEX.replace(current) { match ->
                match.groupValues[1]
            }
            if (replaced == current) return replaced
            current = replaced
        }
    }

    private fun normalizeMinutesTokens(text: String): String {
        return MINUTES_REGEX.replace(text, "minutes")
    }

    private fun resolveCorrectionTurns(text: String): String {
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
        if (hasDigit(oldTrimmed) || hasDigit(replacementTrimmed)) return true
        if (containsCardinalWord(oldTrimmed) || containsCardinalWord(replacementTrimmed)) return true
        return oldTrimmed.split(WHITESPACE_REGEX).size <= 2 &&
            replacementTrimmed.split(WHITESPACE_REGEX).size <= 2
    }

    private fun hasDigit(text: String): Boolean {
        return DIGIT_REGEX.containsMatchIn(text)
    }

    private fun containsCardinalWord(text: String): Boolean {
        val tokens = text
            .lowercase()
            .replace('-', ' ')
            .split(WHITESPACE_REGEX)
            .filter { it.isNotBlank() }
        return tokens.any { token -> token in ALL_NUMBER_WORDS }
    }

    private fun normalizeNumberWordsToDigits(text: String): String {
        return NUMBER_SEQUENCE_REGEX.replace(text) { match ->
            val converted = convertNumberPhrase(match.value)
            converted ?: match.value
        }
    }

    private fun convertNumberPhrase(phrase: String): String? {
        val tokens = phrase
            .lowercase()
            .replace('-', ' ')
            .split(WHITESPACE_REGEX)
            .filter { it.isNotBlank() }
        if (tokens.isEmpty()) return null
        if (tokens.any { token -> token !in ALL_NUMBER_WORDS && token != "and" }) return null

        if (tokens.size >= 2 && tokens.all { token -> token in DIGIT_WORDS }) {
            return tokens.joinToString(separator = "") { token ->
                DIGIT_WORDS.getValue(token).toString()
            }
        }

        var total = 0
        var current = 0
        var consumed = false

        tokens.forEach { token ->
            when {
                token == "and" -> Unit
                token in DIGIT_WORDS -> {
                    current += DIGIT_WORDS.getValue(token)
                    consumed = true
                }
                token in TEEN_WORDS -> {
                    current += TEEN_WORDS.getValue(token)
                    consumed = true
                }
                token in TENS_WORDS -> {
                    current += TENS_WORDS.getValue(token)
                    consumed = true
                }
                token == "hundred" -> {
                    current = (if (current == 0) 1 else current) * 100
                    consumed = true
                }
                token == "thousand" -> {
                    val block = if (current == 0) 1 else current
                    total += block * 1000
                    current = 0
                    consumed = true
                }
                else -> return null
            }
        }

        if (!consumed) return null
        return (total + current).toString()
    }

    private fun normalizeSurface(text: String): String {
        return text
            .replace(SPACE_BEFORE_PUNCTUATION_REGEX, "$1")
            .replace(DUPLICATE_COMMA_REGEX, ",")
            .replace(ORPHAN_COMMA_REGEX, "")
            .replace(MULTI_SPACE_REGEX, " ")
            .trim()
    }

    companion object {
        private val WHITESPACE_REGEX = Regex("\\s+")
        private val MULTI_SPACE_REGEX = Regex(" {2,}")
        private val DIGIT_REGEX = Regex("\\d")
        private val FILLER_TOKEN_REGEX = Regex(
            "(?i)\\b(?:um+|uh+|uhh+|erm+|emm+|hmm+)\\b"
        )
        private val ADJACENT_DUPLICATE_REGEX = Regex(
            "(?i)\\b([\\p{L}\\p{N}']+)\\b(?:\\s+\\1\\b)+"
        )
        private val MINUTES_REGEX = Regex("(?i)\\bmins?\\b")
        private val SPACE_BEFORE_PUNCTUATION_REGEX = Regex("\\s+([,.;!?])")
        private val DUPLICATE_COMMA_REGEX = Regex(",\\s*,+")
        private val ORPHAN_COMMA_REGEX = Regex(",\\s*(?=[.!?]|$)")

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

        private val DIGIT_WORDS = mapOf(
            "zero" to 0,
            "one" to 1,
            "two" to 2,
            "three" to 3,
            "four" to 4,
            "five" to 5,
            "six" to 6,
            "seven" to 7,
            "eight" to 8,
            "nine" to 9
        )
        private val TEEN_WORDS = mapOf(
            "ten" to 10,
            "eleven" to 11,
            "twelve" to 12,
            "thirteen" to 13,
            "fourteen" to 14,
            "fifteen" to 15,
            "sixteen" to 16,
            "seventeen" to 17,
            "eighteen" to 18,
            "nineteen" to 19
        )
        private val TENS_WORDS = mapOf(
            "twenty" to 20,
            "thirty" to 30,
            "forty" to 40,
            "fifty" to 50,
            "sixty" to 60,
            "seventy" to 70,
            "eighty" to 80,
            "ninety" to 90
        )
        private val SCALE_WORDS = setOf("hundred", "thousand")
        private val ALL_NUMBER_WORDS = DIGIT_WORDS.keys + TEEN_WORDS.keys + TENS_WORDS.keys + SCALE_WORDS
        private val NUMBER_WORD_PATTERN = ALL_NUMBER_WORDS.joinToString(separator = "|")
        private val NUMBER_SEQUENCE_REGEX = Regex(
            "(?i)\\b(?:$NUMBER_WORD_PATTERN)(?:[\\s-]+(?:$NUMBER_WORD_PATTERN|and))*\\b"
        )
    }
}
