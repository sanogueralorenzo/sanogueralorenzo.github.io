package com.sanogueralorenzo.voice.ime

import org.junit.Assert.assertEquals
import org.junit.Test

class TextStageTest {
    private val stage = TextStage()

    @Test
    fun formerLlmKeywordsArePlainDictation() {
        listOf("fix", "short.", "message").forEach { transcript ->
            val result = stage.process(
                sourceText = "Existing text",
                transcript = transcript
            )

            assertEquals(ImeOperation.APPEND, result.operation)
            assertEquals("Existing text $transcript", result.output)
        }
    }

    @Test
    fun deterministicEditCommandsRemainSupported() {
        val result = stage.process(
            sourceText = "Buy milk and eggs",
            transcript = "delete milk"
        )

        assertEquals(ImeOperation.EDIT, result.operation)
        assertEquals("Buy and eggs", result.output)
    }
}
