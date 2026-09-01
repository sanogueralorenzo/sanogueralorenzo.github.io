package com.sanogueralorenzo.voice.audio

/** Combines existing editor text with Moonshine's finalized and provisional lines. */
internal class DictationTextBuffer(originalText: String) {
    private val originalText = originalText.trimEnd()
    private val completedLines = LinkedHashMap<Long, String>()
    private var partialText = ""

    val hasTranscript: Boolean
        get() = completedLines.isNotEmpty() || partialText.isNotBlank()

    fun updatePartial(text: String): String {
        partialText = text.trim()
        return currentText()
    }

    fun completeLine(id: Long, text: String): String {
        val finalText = text.trim()
        if (finalText.isNotEmpty()) {
            completedLines[id] = finalText
        }
        partialText = ""
        return currentText()
    }

    fun originalText(): String = originalText

    fun currentText(): String {
        val transcript = buildList {
            addAll(completedLines.values)
            if (partialText.isNotBlank()) add(partialText)
        }.joinToString(" ").trim()
        return when {
            originalText.isBlank() -> transcript
            transcript.isBlank() -> originalText
            else -> "$originalText $transcript"
        }
    }
}
