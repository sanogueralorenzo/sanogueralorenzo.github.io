package com.sanogueralorenzo.voice.summary.rules.pre

import com.sanogueralorenzo.voice.engine.VoiceEngine

/**
 * Deterministic pre-LLM rewrite for compose input.
 *
 * Possible outcomes:
 * - Returns unchanged text with `changed=false` and no applied rules.
 * - Returns normalized text with `changed=true` and the set of rules applied.
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
        val result = VoiceEngine.preprocess(input)
        return Result(
            text = result.text,
            changed = result.changed,
            appliedRules = result.appliedRuleIds.mapNotNull { ruleId ->
                runCatching { Rule.valueOf(ruleId) }.getOrNull()
            }.toCollection(linkedSetOf())
        )
    }
}
