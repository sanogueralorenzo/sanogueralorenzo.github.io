package com.sanogueralorenzo.voice.summary.rules.pre

internal class StandaloneFillerRule : PreLlmRule {
    override fun apply(text: String): String {
        return FILLER_TOKEN_REGEX.replace(text, " ")
    }

    private companion object {
        private val FILLER_TOKEN_REGEX = Regex(
            "(?i)\\b(?:um+|uh+|uhh+|erm+|emm+|hmm+)\\b"
        )
    }
}
