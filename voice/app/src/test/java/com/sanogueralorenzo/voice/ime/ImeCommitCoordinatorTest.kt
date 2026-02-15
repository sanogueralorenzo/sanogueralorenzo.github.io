package com.sanogueralorenzo.voice.ime

import com.sanogueralorenzo.voice.summary.LiteRtEditHeuristics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImeCommitCoordinatorTest {
    private val coordinator = ImeCommitCoordinator()

    @Test
    fun composeNonBlank_enqueuesCommit() {
        var enqueuedText: String? = null
        var replaced = false

        val result = coordinator.commit(
            mode = ImeSendMode.COMPOSE_NEW,
            outputForCommit = "hello world",
            editIntent = null,
            sessionId = 12,
            packageName = "pkg",
            isSessionCurrent = { _, _ -> true },
            replaceCurrentInputText = {
                replaced = true
                true
            },
            enqueuePendingCommit = { text, _, _ ->
                enqueuedText = text
            }
        )

        assertTrue(result.committed)
        assertFalse(result.sessionMismatch)
        assertFalse(replaced)
        assertEquals("hello world", enqueuedText)
    }

    @Test
    fun editBlankNonDelete_preservesSource() {
        var replaced = false

        val result = coordinator.commit(
            mode = ImeSendMode.EDIT_EXISTING,
            outputForCommit = "",
            editIntent = "REPLACE_TERM",
            sessionId = 1,
            packageName = "pkg",
            isSessionCurrent = { _, _ -> true },
            replaceCurrentInputText = {
                replaced = true
                true
            },
            enqueuePendingCommit = { _, _, _ -> }
        )

        assertTrue(result.committed)
        assertFalse(result.sessionMismatch)
        assertFalse(replaced)
    }

    @Test
    fun editBlankDeleteAll_clearsSource() {
        var replacedText: String? = null

        val result = coordinator.commit(
            mode = ImeSendMode.EDIT_EXISTING,
            outputForCommit = "",
            editIntent = LiteRtEditHeuristics.EditIntent.DELETE_ALL.name,
            sessionId = 1,
            packageName = "pkg",
            isSessionCurrent = { _, _ -> true },
            replaceCurrentInputText = {
                replacedText = it
                true
            },
            enqueuePendingCommit = { _, _, _ -> }
        )

        assertTrue(result.committed)
        assertEquals("", replacedText)
    }

    @Test
    fun sessionMismatch_doesNotCommit() {
        var replaced = false
        var enqueued = false

        val result = coordinator.commit(
            mode = ImeSendMode.COMPOSE_NEW,
            outputForCommit = "text",
            editIntent = null,
            sessionId = 1,
            packageName = "pkg",
            isSessionCurrent = { _, _ -> false },
            replaceCurrentInputText = {
                replaced = true
                true
            },
            enqueuePendingCommit = { _, _, _ ->
                enqueued = true
            }
        )

        assertFalse(result.committed)
        assertTrue(result.sessionMismatch)
        assertFalse(replaced)
        assertFalse(enqueued)
    }
}
