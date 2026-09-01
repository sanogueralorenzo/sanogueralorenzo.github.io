package com.sanogueralorenzo.voice.command

internal enum class LlmCommand {
    FIX,
    SHORTEN,
    MESSAGE;

    companion object {
        fun fromExactTranscript(transcript: String): LlmCommand? {
            val candidate = transcript.trim()
            return entries.firstOrNull { command ->
                candidate.equals(command.name, ignoreCase = true)
            }
        }
    }
}
