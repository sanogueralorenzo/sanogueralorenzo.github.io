package com.sanogueralorenzo.voice.summary

/**
 * Deterministic input/output policy for compose cleanup.
 * Keeps rewrite behavior constrained to minimal dictation-safe edits.
 */
class LiteRtComposePolicy {
    fun normalizeComposeInput(text: String): String {
        val collapsed = text.replace(WHITESPACE_REGEX, " ").trim()
        if (collapsed.isBlank()) return ""
        return collapsed
            .replace(REPEATED_FILLER_REGEX, "$1")
            .replace(SPACE_BEFORE_PUNCTUATION_REGEX, "$1")
            .replace(REPEATED_PUNCTUATION_REGEX, "$1")
            .trim()
    }

    fun normalizeInstructionInput(text: String): String {
        return text.replace(WHITESPACE_REGEX, " ").trim()
    }

    fun cleanModelOutput(
        text: String,
        bulletMode: Boolean
    ): String {
        var cleaned = text.trim()
        if (cleaned.isBlank()) return ""
        val anchorMatches = CLEANED_ANCHOR_REGEX.findAll(cleaned).toList()
        if (anchorMatches.isNotEmpty()) {
            cleaned = cleaned.substring(anchorMatches.last().range.last + 1).trim()
        }
        cleaned = cleaned
            .replace(PREFIX_LABEL_REGEX, "")
            .trim()
            .trim('`')
            .trim()
            .removeSurrounding("\"")
            .removeSurrounding("'")
            .trim()
        if (cleaned.isBlank()) return ""
        if (cleaned.startsWith("user input:", ignoreCase = true)) {
            val nonEmptyLines = cleaned
                .lineSequence()
                .map { it.trim() }
                .filter { it.isNotBlank() }
                .toList()
            if (nonEmptyLines.size >= 2) {
                cleaned = nonEmptyLines.last()
            }
        }
        if (!bulletMode && cleaned.startsWith("- ")) {
            cleaned = cleaned
                .lineSequence()
                .map { it.removePrefix("- ").trim() }
                .filter { it.isNotBlank() }
                .joinToString(" ")
        }
        return cleaned
    }

    fun finalizeComposeOutput(
        originalText: String,
        modelOutput: String,
        listMode: Boolean
    ): String {
        val original = originalText.trim()
        val candidate = cleanModelOutput(modelOutput, bulletMode = listMode).trim()
        if (original.isBlank()) return candidate
        if (candidate.isBlank()) return original
        if (isExcessiveLengthShift(original = original, candidate = candidate)) return original
        if (looksLikeAssistantReply(original = original, candidate = candidate)) return original
        if (isLowTokenOverlap(original = original, candidate = candidate)) return original
        return candidate
    }

    private fun isExcessiveLengthShift(
        original: String,
        candidate: String
    ): Boolean {
        val originalChars = original.length
        val candidateChars = candidate.length
        val expandedTooMuch =
            candidateChars > (originalChars * MAX_OUTPUT_EXPANSION_MULTIPLIER).toInt() &&
                (candidateChars - originalChars) > MAX_OUTPUT_EXPANSION_DELTA_CHARS
        if (expandedTooMuch) return true
        val compressedTooMuch =
            candidateChars < (originalChars * MIN_OUTPUT_COMPRESSION_MULTIPLIER).toInt() &&
                (originalChars - candidateChars) > MAX_OUTPUT_COMPRESSION_DELTA_CHARS
        return compressedTooMuch
    }

    private fun looksLikeAssistantReply(
        original: String,
        candidate: String
    ): Boolean {
        val candidateLower = candidate.lowercase()
        if (!ASSISTANT_REPLY_PREFIXES.any { prefix -> candidateLower.startsWith(prefix) }) {
            return false
        }
        val originalLower = original.lowercase()
        return ASSISTANT_REPLY_PREFIXES.none { prefix -> originalLower.startsWith(prefix) }
    }

    private fun isLowTokenOverlap(
        original: String,
        candidate: String
    ): Boolean {
        val originalTokens = WORD_TOKEN_REGEX.findAll(original.lowercase()).map { it.value }.toList()
        val candidateTokens = WORD_TOKEN_REGEX.findAll(candidate.lowercase()).map { it.value }.toList()
        if (originalTokens.size < MIN_TOKENS_FOR_OVERLAP_GUARD) return false
        if (candidateTokens.size < MIN_TOKENS_FOR_OVERLAP_GUARD) return false
        val originalSet = originalTokens.toSet()
        val overlapCount = candidateTokens.count { token -> token in originalSet }
        val overlapRatio = overlapCount.toDouble() / candidateTokens.size.toDouble()
        return overlapRatio < MIN_OVERLAP_RATIO
    }

    companion object {
        private const val MAX_OUTPUT_EXPANSION_MULTIPLIER = 1.5
        private const val MIN_OUTPUT_COMPRESSION_MULTIPLIER = 0.5
        private const val MAX_OUTPUT_EXPANSION_DELTA_CHARS = 20
        private const val MAX_OUTPUT_COMPRESSION_DELTA_CHARS = 20
        private const val MIN_TOKENS_FOR_OVERLAP_GUARD = 4
        private const val MIN_OVERLAP_RATIO = 0.55

        private val ASSISTANT_REPLY_PREFIXES = listOf(
            "sure",
            "yes",
            "no problem",
            "absolutely",
            "i can",
            "here"
        )
        private val WHITESPACE_REGEX = Regex("\\s+")
        private val REPEATED_FILLER_REGEX = Regex(
            "\\b(um+|uh+|erm+|emm+|hmm+)(?:\\s+\\1\\b)+",
            RegexOption.IGNORE_CASE
        )
        private val SPACE_BEFORE_PUNCTUATION_REGEX = Regex("\\s+([,.;!?])")
        private val REPEATED_PUNCTUATION_REGEX = Regex("([,.;!?])\\1+")
        private val PREFIX_LABEL_REGEX = Regex(
            "^(rewritten|rewrite|cleaned|output|result)\\s*:\\s*",
            RegexOption.IGNORE_CASE
        )
        private val CLEANED_ANCHOR_REGEX = Regex(
            "^cleaned\\s*:\\s*",
            setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE)
        )
        private val WORD_TOKEN_REGEX = Regex("\\b[\\p{L}\\p{N}']+\\b")
    }
}
