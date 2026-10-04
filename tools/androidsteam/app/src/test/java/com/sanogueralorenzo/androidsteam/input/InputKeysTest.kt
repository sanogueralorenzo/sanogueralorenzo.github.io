package com.sanogueralorenzo.androidsteam.input

import org.junit.Assert.assertEquals
import org.junit.Test

class InputKeysTest {
    @Test fun simultaneousSourcesDoNotCancelHeldKeysAndClearReleasesEachOnce() {
        val events = mutableListOf<Pair<Int, Boolean>>()
        val input = InputKeys { code, pressed -> events += code to pressed }
        input.set("stick", setOf(105))
        input.set("keyboard", setOf(105))
        input.set("stick", setOf(106))
        assertEquals(listOf(105 to true, 106 to true), events)
        input.set("keyboard", emptySet())
        input.set("button", setOf(28))
        input.clear(); input.clear()
        assertEquals(listOf(105 to true, 106 to true, 105 to false, 28 to true, 106 to false, 28 to false), events)
    }

    @Test fun digitalMovementSupportsDiagonalsAndCenteredRelease() {
        assertEquals(setOf(105, 103), ControlProfile.ARROWS.movement(-1f, -1f))
        assertEquals(setOf(32, 31), ControlProfile.WASD.movement(1f, 1f))
        assertEquals(emptySet<Int>(), ControlProfile.ARROWS.movement(.1f, -.2f))
    }
}
