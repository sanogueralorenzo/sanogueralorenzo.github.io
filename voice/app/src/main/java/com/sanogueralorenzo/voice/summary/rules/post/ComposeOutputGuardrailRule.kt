package com.sanogueralorenzo.voice.summary.rules.post

internal class ComposeOutputGuardrailRule {
    fun choose(
        original: String,
        candidate: String
    ): String {
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

    private companion object {
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
        private val WORD_TOKEN_REGEX = Regex("\\b[\\p{L}\\p{N}']+\\b")
    }
}
