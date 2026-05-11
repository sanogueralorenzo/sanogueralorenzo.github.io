package com.sanogueralorenzo.voice.summary.rules.post

internal class SpokenNumberOutputRule {
    fun apply(text: String): String {
        return SPOKEN_NUMBER_SEQUENCE_REGEX.replace(text) { match ->
            spokenNumberToDigits(match.value) ?: match.value
        }
    }

    private fun spokenNumberToDigits(text: String): String? {
        val words = text
            .lowercase()
            .replace(NUMBER_SEPARATOR_REGEX, " ")
            .split(WHITESPACE_REGEX)
            .map { it.trim() }
            .filter { it.isNotBlank() && it != "and" }
        if (words.isEmpty()) return null
        if (words.any { it !in NUMBER_WORDS }) return null
        if (words.size == 1) return null
        if (words.size > 1 && words.all { it in DIGIT_WORDS }) {
            return words.joinToString("") { DIGIT_WORDS.getValue(it).toString() }
        }
        return parseCardinalNumber(words)?.toString()
    }

    private fun parseCardinalNumber(words: List<String>): Long? {
        return parseScaledCardinal(words = words, scaleWord = "million", scaleValue = 1_000_000L)
            ?: parseScaledCardinal(words = words, scaleWord = "thousand", scaleValue = 1_000L)
            ?: parseUnderThousand(words)
    }

    private fun parseScaledCardinal(
        words: List<String>,
        scaleWord: String,
        scaleValue: Long
    ): Long? {
        val scaleIndex = words.indexOf(scaleWord)
        if (scaleIndex <= 0) return null
        if (words.indexOfLast { it == scaleWord } != scaleIndex) return null
        val prefix = parseUnderThousand(words.take(scaleIndex)) ?: return null
        if (prefix == 0L) return null
        val suffixWords = words.drop(scaleIndex + 1)
        val suffix = if (suffixWords.isEmpty()) {
            0L
        } else {
            parseCardinalNumber(suffixWords) ?: return null
        }
        return prefix * scaleValue + suffix
    }

    private fun parseUnderThousand(words: List<String>): Long? {
        if (words.isEmpty()) return null
        val hundredIndex = words.indexOf("hundred")
        if (hundredIndex >= 0) {
            if (hundredIndex != 1) return null
            if (words.indexOfLast { it == "hundred" } != hundredIndex) return null
            val hundreds = DIGIT_WORDS[words.first()] ?: return null
            if (hundreds == 0L) return null
            val remainderWords = words.drop(2)
            val remainder = if (remainderWords.isEmpty()) {
                0L
            } else {
                parseUnderHundred(remainderWords) ?: return null
            }
            return hundreds * 100L + remainder
        }
        return parseUnderHundred(words)
    }

    private fun parseUnderHundred(words: List<String>): Long? {
        return when (words.size) {
            1 -> SMALL_NUMBER_WORDS[words.first()] ?: TENS_WORDS[words.first()]
            2 -> {
                val tens = TENS_WORDS[words[0]] ?: return null
                val ones = DIGIT_WORDS[words[1]] ?: return null
                if (ones == 0L) return null
                tens + ones
            }
            else -> null
        }
    }

    private companion object {
        private val WHITESPACE_REGEX = Regex("\\s+")
        private val SMALL_NUMBER_WORDS = mapOf(
            "zero" to 0L,
            "one" to 1L,
            "two" to 2L,
            "three" to 3L,
            "four" to 4L,
            "five" to 5L,
            "six" to 6L,
            "seven" to 7L,
            "eight" to 8L,
            "nine" to 9L,
            "ten" to 10L,
            "eleven" to 11L,
            "twelve" to 12L,
            "thirteen" to 13L,
            "fourteen" to 14L,
            "fifteen" to 15L,
            "sixteen" to 16L,
            "seventeen" to 17L,
            "eighteen" to 18L,
            "nineteen" to 19L
        )
        private val TENS_WORDS = mapOf(
            "twenty" to 20L,
            "thirty" to 30L,
            "forty" to 40L,
            "fifty" to 50L,
            "sixty" to 60L,
            "seventy" to 70L,
            "eighty" to 80L,
            "ninety" to 90L
        )
        private val DIGIT_WORDS = SMALL_NUMBER_WORDS.filterValues { it in 0L..9L }
        private val NUMBER_WORDS = SMALL_NUMBER_WORDS.keys +
            TENS_WORDS.keys +
            setOf("hundred", "thousand", "million")
        private val NUMBER_WORD_PATTERN = NUMBER_WORDS.joinToString("|")
        private val SPOKEN_NUMBER_SEQUENCE_REGEX = Regex(
            "\\b(?:$NUMBER_WORD_PATTERN)(?:(?:\\s*,\\s*|\\s+|-)(?:and\\s+)?(?:$NUMBER_WORD_PATTERN))*\\b",
            RegexOption.IGNORE_CASE
        )
        private val NUMBER_SEPARATOR_REGEX = Regex("[,\\-]")
    }
}
