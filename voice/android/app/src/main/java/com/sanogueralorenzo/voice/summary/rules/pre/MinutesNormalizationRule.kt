package com.sanogueralorenzo.voice.summary.rules.pre

internal class MinutesNormalizationRule : PreLlmRule {
    override fun apply(text: String): String {
        return MINUTES_REGEX.replace(text, "minutes")
    }

    private companion object {
        private val MINUTES_REGEX = Regex("(?i)\\bmins?\\b")
    }
}
