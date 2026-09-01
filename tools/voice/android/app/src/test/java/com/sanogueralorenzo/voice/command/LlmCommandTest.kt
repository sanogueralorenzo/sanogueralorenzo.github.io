package com.sanogueralorenzo.voice.command

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LlmCommandTest {
    @Test
    fun recognizesOnlyExactCommandWords() {
        assertEquals(LlmCommand.FIX, LlmCommand.fromExactTranscript("fix"))
        assertEquals(LlmCommand.SHORTEN, LlmCommand.fromExactTranscript(" SHORTEN "))
        assertEquals(LlmCommand.MESSAGE, LlmCommand.fromExactTranscript("Message"))

        assertNull(LlmCommand.fromExactTranscript("polish"))
        assertNull(LlmCommand.fromExactTranscript("please fix"))
        assertNull(LlmCommand.fromExactTranscript("fix this"))
        assertNull(LlmCommand.fromExactTranscript("make it shorter"))
        assertNull(LlmCommand.fromExactTranscript("message Alex"))
        assertNull(LlmCommand.fromExactTranscript("fix."))
    }
}
