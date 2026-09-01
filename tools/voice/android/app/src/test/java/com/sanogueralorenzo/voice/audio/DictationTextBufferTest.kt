package com.sanogueralorenzo.voice.audio

import org.junit.Assert.assertEquals
import org.junit.Test

class DictationTextBufferTest {
    @Test
    fun partialTextReplacesThePreviousPartial() {
        val buffer = DictationTextBuffer("Existing text")

        assertEquals("Existing text hello", buffer.updatePartial("hello"))
        assertEquals("Existing text hello there", buffer.updatePartial("hello there"))
        assertEquals("Existing text", buffer.updatePartial(""))
    }

    @Test
    fun completedLineReplacesThePartialAndKeepsLaterSpeechSeparate() {
        val buffer = DictationTextBuffer("")

        buffer.updatePartial("hello their")
        assertEquals("Hello there.", buffer.completeLine(1L, "Hello there."))
        assertEquals("Hello there. How are", buffer.updatePartial("How are"))
        assertEquals("Hello there. How are you?", buffer.completeLine(2L, "How are you?"))
    }

    @Test
    fun repeatedFinalCallbackUpdatesTheSameLine() {
        val buffer = DictationTextBuffer("")

        buffer.completeLine(7L, "First version")

        assertEquals("Final version", buffer.completeLine(7L, "Final version"))
    }
}
