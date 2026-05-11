package com.sanogueralorenzo.voice.summary.rules.pre

internal class NumberWordsToDigitsRule : PreLlmRule {
    override fun apply(text: String): String {
        return NUMBER_SEQUENCE_REGEX.replace(text) { match ->
            convertNumberPhrase(match.value) ?: match.value
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

    internal companion object {
        private val WHITESPACE_REGEX = Regex("\\s+")
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
        val ALL_NUMBER_WORDS = DIGIT_WORDS.keys + TEEN_WORDS.keys + TENS_WORDS.keys + SCALE_WORDS
        private val NUMBER_WORD_PATTERN = ALL_NUMBER_WORDS.joinToString(separator = "|")
        private val NUMBER_SEQUENCE_REGEX = Regex(
            "(?i)\\b(?:$NUMBER_WORD_PATTERN)(?:[\\s-]+(?:$NUMBER_WORD_PATTERN|and))*\\b"
        )
    }
}
