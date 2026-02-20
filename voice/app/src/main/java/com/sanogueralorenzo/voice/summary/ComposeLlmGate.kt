package com.sanogueralorenzo.voice.summary

/**
 * Determines whether compose flow should call the LLM after deterministic rewrite.
 * Only typo-like cases should fall through to LLM.
 */
class ComposeLlmGate {
    fun shouldUseLlm(
        originalText: String,
        deterministicResult: ComposePreLlmRules.Result
    ): Boolean {
        if (originalText.isBlank()) return false
        if (deterministicResult.changed) return false
        val typoSignals = TYPO_SIGNAL_PATTERNS.count { pattern ->
            pattern.containsMatchIn(originalText)
        }
        if (typoSignals == 0) return false
        return typoSignals <= MAX_ALLOWED_TYPO_SIGNALS
    }

    companion object {
        private const val MAX_ALLOWED_TYPO_SIGNALS = 2
        private val TYPO_SIGNAL_PATTERNS = listOf(
            Regex("(?i)\\byour\\s+(done|welcome|right|going|late)\\b"),
            Regex("(?i)\\bnite\\b"),
            Regex("(?i)\\b(?:im|ive|id|dont|cant|wont|isnt|arent|didnt|couldnt|shouldnt|wouldnt)\\b"),
            Regex("(?i)\\bteh\\b"),
            Regex("(?i)\\brecieve\\b"),
            Regex("(?i)\\bseperate\\b"),
            Regex("(?i)\\bdefinately\\b")
        )
    }
}
