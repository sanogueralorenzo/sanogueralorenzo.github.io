package com.sanogueralorenzo.voice.overlay

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FocusedInputTextTest {
    @Test
    fun showingHintFlagTakesPriority() {
        assertTrue(
            textRepresentsHint(
                text = "Message",
                showingHintText = true,
                hintText = null,
                hasEditableContent = { error("Selection probe should not run") }
            )
        )
    }

    @Test
    fun matchingHintTextTakesPriority() {
        assertTrue(
            textRepresentsHint(
                text = "Message",
                showingHintText = false,
                hintText = "Message",
                hasEditableContent = { error("Selection probe should not run") }
            )
        )
    }

    @Test
    fun selectionProbeDetectsUnmarkedHint() {
        assertTrue(
            textRepresentsHint(
                text = "Message",
                showingHintText = false,
                hintText = null,
                hasEditableContent = { false }
            )
        )
    }

    @Test
    fun selectionProbePreservesRealText() {
        assertFalse(
            textRepresentsHint(
                text = "Existing message",
                showingHintText = false,
                hintText = null,
                hasEditableContent = { true }
            )
        )
    }
}
