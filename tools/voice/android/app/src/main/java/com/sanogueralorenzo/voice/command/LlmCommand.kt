package com.sanogueralorenzo.voice.command

internal enum class LlmCommand {
    FIX,
    SHORT,
    MESSAGE;

    companion object {
        fun fromExactTranscript(transcript: String): LlmCommand? {
            val candidate = transcript.trim().removeSuffix(".").trimEnd()
            return entries.firstOrNull { command ->
                candidate.equals(command.name, ignoreCase = true)
            }
        }
    }
}
