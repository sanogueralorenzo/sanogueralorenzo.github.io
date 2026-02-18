package com.sanogueralorenzo.voice.ime

import com.sanogueralorenzo.voice.summary.LiteRtEditHeuristics
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ImeCommitCoordinatorTest {
    private val coordinator = ImeCommitCoordinator()

    @Test
    fun appendNonBlank_replacesInput() {
        var replacedText: String? = null

        val result = coordinator.commit(
            operation = ImeOperation.APPEND,
            outputForCommit = "hello world",
            editIntent = null,
            sessionId = 12,
            packageName = "pkg",
            isSessionCurrent = { _, _ -> true },
            replaceCurrentInputText = {
                replacedText = it
                true
            }
        )

        assertTrue(result.committed)
        assertFalse(result.sessionMismatch)
        assertEquals("hello world", replacedText)
    }

    @Test
    fun appendBlank_isNoOp() {
        var replaced = false

        val result = coordinator.commit(
            operation = ImeOperation.APPEND,
            outputForCommit = "",
            editIntent = null,
            sessionId = 1,
            packageName = "pkg",
            isSessionCurrent = { _, _ -> true },
            replaceCurrentInputText = {
                replaced = true
                true
            }
        )

        assertFalse(result.sessionMismatch)
        assertFalse(result.committed)
        assertFalse(replaced)
    }

    @Test
    fun editBlankNonDelete_preservesSource() {
        var replaced = false

        val result = coordinator.commit(
            operation = ImeOperation.EDIT,
            outputForCommit = "",
            editIntent = "REPLACE_TERM",
            sessionId = 1,
            packageName = "pkg",
            isSessionCurrent = { _, _ -> true },
            replaceCurrentInputText = {
                replaced = true
                true
            }
        )

        assertTrue(result.committed)
        assertFalse(result.sessionMismatch)
        assertFalse(replaced)
    }

    @Test
    fun editBlankDeleteAll_clearsSource() {
        var replacedText: String? = null

        val result = coordinator.commit(
            operation = ImeOperation.EDIT,
            outputForCommit = "",
            editIntent = LiteRtEditHeuristics.EditIntent.DELETE_ALL.name,
            sessionId = 1,
            packageName = "pkg",
            isSessionCurrent = { _, _ -> true },
            replaceCurrentInputText = {
                replacedText = it
                true
            }
        )

        assertTrue(result.committed)
        assertEquals("", replacedText)
    }

    @Test
    fun sessionMismatch_doesNotCommit() {
        var replaced = false

        val result = coordinator.commit(
            operation = ImeOperation.APPEND,
            outputForCommit = "text",
            editIntent = null,
            sessionId = 1,
            packageName = "pkg",
            isSessionCurrent = { _, _ -> false },
            replaceCurrentInputText = {
                replaced = true
                true
            }
        )

        assertFalse(result.committed)
        assertTrue(result.sessionMismatch)
        assertFalse(replaced)
    }
}
