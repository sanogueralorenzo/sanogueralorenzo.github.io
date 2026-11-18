package com.sanogueralorenzo.voice.dictation

/** Combines existing editor text with Moonshine's finalized and provisional lines. */
internal class DictationTextBuffer(originalText: String) {
    private val originalText = originalText.trimEnd()
    private val completedLines = LinkedHashMap<Long, String>()
    private var partialText = ""

    val hasTranscript: Boolean
        get() = completedLines.isNotEmpty() || partialText.isNotBlank()

    fun updatePartial(text: String): String {
        partialText = text.trim()
        return liveText()
    }

    fun completeLine(id: Long, text: String): String {
        val finalText = text.trim()
        if (finalText.isNotEmpty()) {
            completedLines[id] = finalText
        }
        partialText = ""
        return liveText()
    }

    fun originalText(): String = originalText

    fun command(): DictationEditCommand? = DictationEditCommands.parse(transcriptText())

    fun currentText(): String {
        val transcript = transcriptText()
        command()?.let { return it.applyTo(originalText) }
        return combineWithOriginal(transcript)
    }

    fun transcriptText(): String = buildList {
        addAll(completedLines.values)
        if (partialText.isNotBlank()) add(partialText)
    }.joinToString(" ").trim()

    private fun liveText(): String {
        val transcript = transcriptText()
        return if (DictationEditCommands.isPotentialCommand(transcript)) {
            originalText
        } else {
            combineWithOriginal(transcript)
        }
    }

    private fun combineWithOriginal(transcript: String): String {
        return when {
            originalText.isBlank() -> transcript
            transcript.isBlank() -> originalText
            else -> "$originalText $transcript"
        }
    }
}
