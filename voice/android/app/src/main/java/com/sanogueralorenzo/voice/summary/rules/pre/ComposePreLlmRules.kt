package com.sanogueralorenzo.voice.summary.rules.pre

/**
 * Deterministic pre-LLM rewrite for compose input.
 *
 * Possible outcomes:
 * - Returns unchanged text with `changed=false` and no applied rules.
 * - Returns normalized text with `changed=true` and the set of rules applied.
 */
class ComposePreLlmRules {
    private data class TrackedRule(
        val rule: Rule,
        val implementation: PreLlmRule
    )

    private val rules = listOf(
        TrackedRule(Rule.FILLER, StandaloneFillerRule()),
        TrackedRule(Rule.ADJACENT_DUPLICATE, AdjacentDuplicateRule()),
        TrackedRule(Rule.MINUTES_NORMALIZATION, MinutesNormalizationRule()),
        TrackedRule(Rule.CORRECTION_TURN, CorrectionTurnRule()),
        TrackedRule(Rule.NUMBER_WORDS_TO_DIGITS, NumberWordsToDigitsRule())
    )
    private val surfaceCleanupRule = SurfaceCleanupRule()

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

        for (trackedRule in rules) {
            val updated = trackedRule.implementation.apply(current)
            if (updated != current) {
                applied += trackedRule.rule
                current = updated
            }
        }

        val finalText = surfaceCleanupRule.apply(current)
        return Result(
            text = finalText,
            changed = finalText != source,
            appliedRules = applied
        )
    }
}
