package com.sanogueralorenzo.voice.summary

private val RewriteWhitespaceRegex = Regex("\\s+")
private val RewriteWordRegex = Regex("\\p{L}[\\p{L}\\p{N}'’-]*")

object LiteRtRewritePolicy {
    private const val BASE_TIMEOUT_MS = 2_200L
    private const val FRESH_ENGINE_TIMEOUT_MS = 3_200L
    private const val LONG_INPUT_TIMEOUT_BONUS_MS = 400L
    private const val LONG_INPUT_WORD_COUNT = 60
    private const val MAX_RUNTIME_CUSTOM_INSTRUCTIONS_CHARS = 220

    fun adaptiveTimeoutMs(inputText: String, rewritesSinceEngineInit: Int): Long {
        val wordCount = countWords(inputText)
        val base = if (rewritesSinceEngineInit < 2) {
            FRESH_ENGINE_TIMEOUT_MS
        } else {
            BASE_TIMEOUT_MS
        }
        return if (wordCount > LONG_INPUT_WORD_COUNT) {
            base + LONG_INPUT_TIMEOUT_BONUS_MS
        } else {
            base
        }
    }

    fun countWords(text: String): Int {
        val cleaned = text.replace(RewriteWhitespaceRegex, " ").trim()
        if (cleaned.isBlank()) return 0
        return RewriteWordRegex.findAll(cleaned).count()
    }

    fun isInvalidArgumentError(error: Throwable): Boolean {
        var current: Throwable? = error
        while (current != null) {
            val message = current.message.orEmpty()
            if (
                message.contains("INVALID_ARGUMENT", ignoreCase = true) ||
                message.contains("Unprocessed token is null", ignoreCase = true)
            ) {
                return true
            }
            current = current.cause
        }
        return false
    }

    fun isInputTooLongError(error: Throwable): Boolean {
        var current: Throwable? = error
        while (current != null) {
            val message = current.message.orEmpty()
            if (
                message.contains("Input token ids are too long", ignoreCase = true) ||
                message.contains("Exceeding the maximum number of tokens allowed", ignoreCase = true)
            ) {
                return true
            }
            current = current.cause
        }
        return false
    }

    fun clipCustomInstructions(text: String): String {
        return text
            .replace("\r\n", "\n")
            .trim()
            .take(MAX_RUNTIME_CUSTOM_INSTRUCTIONS_CHARS)
    }
}
