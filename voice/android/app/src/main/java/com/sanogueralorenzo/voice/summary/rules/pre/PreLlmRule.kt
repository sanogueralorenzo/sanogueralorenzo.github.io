package com.sanogueralorenzo.voice.summary.rules.pre

internal fun interface PreLlmRule {
    fun apply(text: String): String
}
