package com.sanogueralorenzo.voice.dictation

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DictationEditCommandTest {
    @Test
    fun clearIgnoresCasePeriodsAndCommas() {
        assertEquals("", DictationEditCommands.parse("CLEAR.,")?.applyTo("Buy milk"))
    }

    @Test
    fun deleteIgnoresCommandAndTargetCase() {
        val command = DictationEditCommands.parse("DELETE, milk.")

        assertEquals("Buy bread", command?.applyTo("Buy MILK bread"))
    }

    @Test
    fun replaceIgnoresCommandAndTargetCase() {
        val command = DictationEditCommands.parse("REPLACE, milk WITH oat milk.")

        assertEquals("Buy oat milk", command?.applyTo("Buy MILK"))
    }

    @Test
    fun commandsMustMatchTheWholeTranscript() {
        assertNull(DictationEditCommands.parse("please clear"))
        assertNull(DictationEditCommands.parse("clear this field"))
        assertNull(DictationEditCommands.parse("some dictation then clear"))
        assertNull(DictationEditCommands.parse("some dictation then delete milk"))
        assertNull(DictationEditCommands.parse("some dictation then replace milk with oat milk"))
        assertNull(DictationEditCommands.parse("replace milk"))
    }

    @Test
    fun potentialCommandsStayOutOfLiveDictation() {
        val buffer = DictationTextBuffer("Buy milk")

        assertEquals("Buy milk", buffer.updatePartial("Replace milk"))
        assertEquals("Buy milk", buffer.updatePartial("Replace milk with oat milk."))
        assertEquals("Buy oat milk", buffer.currentText())
    }
}
