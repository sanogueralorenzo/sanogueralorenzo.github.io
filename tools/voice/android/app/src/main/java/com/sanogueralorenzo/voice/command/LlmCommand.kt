package com.sanogueralorenzo.voice.command

internal enum class LlmCommand(
    val instruction: String
) {
    FIX(
        "Correct transcription, spelling, grammar, and punctuation while preserving the original meaning."
    ),
    SHORTEN(
        "Make the text shorter while preserving its meaning and essential details."
    ),
    MESSAGE(
        "Turn the notes into a concise, natural, send-ready message without inventing details."
    );

    companion object {
        fun fromExactTranscript(transcript: String): LlmCommand? {
            val candidate = transcript.trim()
            return entries.firstOrNull { command ->
                candidate.equals(command.name, ignoreCase = true)
            }
        }
    }
}
