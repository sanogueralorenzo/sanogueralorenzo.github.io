package com.sanogueralorenzo.voice.summary

/**
 * Safety checks to keep rewrite output faithful and prevent out-of-context additions.
 */
internal object LiteRtSafetyGate {
    private const val MIN_WORD_RATIO = 0.72f
    private const val MAX_WORD_RATIO = 1.35f
    private const val NOVEL_TOKEN_RATIO_LIMIT = 0.18f

    fun isSafeRewrite(
        source: String,
        rewritten: String,
        allowStyleNovelty: Boolean
    ): Boolean {
        val candidate = rewritten.trim()
        if (candidate.isBlank()) return false

        val sourceHasDigits = source.any(Char::isDigit)
        val rewrittenHasDigits = candidate.any(Char::isDigit)
        if (sourceHasDigits && !rewrittenHasDigits) return false

        val sourceNumbers = NumberRegex.findAll(source).map { it.value }.toSet()
        val rewrittenNumbers = NumberRegex.findAll(candidate).map { it.value }.toSet()
        if (!rewrittenNumbers.containsAll(sourceNumbers)) return false

        val sourceLinks = LinkRegex.findAll(source).map { it.value.lowercase() }.toSet()
        val rewrittenLinks = LinkRegex.findAll(candidate).map { it.value.lowercase() }.toSet()
        if (!rewrittenLinks.containsAll(sourceLinks)) return false

        if (hasNegation(source) && !hasNegation(candidate)) return false

        val sourceWords = WordRegex.findAll(source).count()
        val rewrittenWords = WordRegex.findAll(candidate).count()
        if (sourceWords >= 8) {
            val ratio = rewrittenWords.toFloat() / sourceWords.toFloat()
            val hasIntentCue = FinalIntentCueRegex.containsMatchIn(source)
            if (ratio < MIN_WORD_RATIO && !hasIntentCue) {
                return false
            }
            if (ratio > MAX_WORD_RATIO && !hasIntentCue) {
                return false
            }
        }

        if (!allowStyleNovelty && exceedsNovelTokenRatio(source, candidate)) {
            return false
        }

        if (hasOutOfContextFiller(source, candidate)) {
            return false
        }

        return true
    }

    private fun exceedsNovelTokenRatio(source: String, rewritten: String): Boolean {
        val sourceLexicon = WordRegex.findAll(source)
            .map { it.value.lowercase() }
            .toSet()
        if (sourceLexicon.isEmpty()) return false

        val rewrittenTokens = WordRegex.findAll(rewritten)
            .map { it.value.lowercase() }
            .toList()
        if (rewrittenTokens.size < 8) return false

        val novelCount = rewrittenTokens.count { token ->
            token.length > 2 &&
                token !in sourceLexicon &&
                token !in FunctionWordAllowlist
        }
        val ratio = novelCount.toFloat() / rewrittenTokens.size.toFloat()
        return ratio > NOVEL_TOKEN_RATIO_LIMIT
    }

    private fun hasOutOfContextFiller(source: String, rewritten: String): Boolean {
        val sourceLower = source.lowercase()
        val rewrittenLower = rewritten.lowercase()
        for (pattern in OutOfContextFillerPatterns) {
            if (pattern.containsMatchIn(rewrittenLower) && !pattern.containsMatchIn(sourceLower)) {
                return true
            }
        }
        return false
    }

    private fun hasNegation(text: String): Boolean {
        return NegationRegex.containsMatchIn(text)
    }

    private val FunctionWordAllowlist = setOf(
        "a", "an", "the", "and", "or", "but", "if", "then", "else", "for", "to", "of", "in",
        "on", "at", "with", "from", "into", "over", "under", "by", "as", "is", "are", "was",
        "were", "be", "been", "being", "do", "does", "did", "have", "has", "had", "i", "you",
        "we", "they", "he", "she", "it", "my", "your", "our", "their", "this", "that", "these",
        "those"
    )

    private val OutOfContextFillerPatterns = listOf(
        Regex("\\blet me know\\b", RegexOption.IGNORE_CASE),
        Regex("\\bfeel free\\b", RegexOption.IGNORE_CASE),
        Regex("\\bhope this helps\\b", RegexOption.IGNORE_CASE),
        Regex("\\bthank you\\b", RegexOption.IGNORE_CASE),
        Regex("\\bthanks\\b", RegexOption.IGNORE_CASE),
        Regex("\\bbest regards\\b", RegexOption.IGNORE_CASE),
        Regex("\\bhave a great\\b", RegexOption.IGNORE_CASE),
        Regex("\\blooking forward\\b", RegexOption.IGNORE_CASE)
    )

    private val WordRegex = Regex("\\p{L}[\\p{L}\\p{N}'’-]*")
    private val NumberRegex = Regex("\\b\\d+(?:[.,:/-]\\d+)*\\b")
    private val LinkRegex = Regex(
        "\\b(?:https?://\\S+|www\\.\\S+|\\S+@\\S+\\.\\S+)\\b",
        RegexOption.IGNORE_CASE
    )
    private val NegationRegex = Regex(
        "\\b(no|not|never|none|don't|doesn't|didn't|can't|cannot|won't|shouldn't|isn't|aren't|wasn't|weren't|without)\\b",
        RegexOption.IGNORE_CASE
    )
    private val FinalIntentCueRegex = Regex(
        "\\b(never\\s?mind|nevermind|scratch\\s+that|actually|instead|rather)\\b",
        RegexOption.IGNORE_CASE
    )
}
