package com.sanogueralorenzo.voice.summary

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LiteRtHardAbortMarkerStoreInstrumentedTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun staleMarker_isDetectedAndCleared() {
        val store = LiteRtHardAbortMarkerStore(context)
        val now = 20_000L
        store.markOperationStart(nowMs = 0L)

        val detected = store.detectAndConsumeStaleMarker(
            staleAfterMs = 10_000L,
            nowMs = now
        )

        assertTrue(detected.suspectedPreviousRunAbort)
        assertTrue(detected.suspectedAbortCount >= 1)

        val statusAfter = store.currentStatus()
        assertFalse(statusAfter.suspectedPreviousRunAbort)
        assertEquals(detected.suspectedAbortCount, statusAfter.suspectedAbortCount)
    }

    @Test
    fun normalLifecycle_doesNotRaiseSuspicion() {
        val store = LiteRtHardAbortMarkerStore(context)
        store.markOperationStart(nowMs = 1_000L)
        store.clearOperationMarker()
        val detected = store.detectAndConsumeStaleMarker(
            staleAfterMs = 10_000L,
            nowMs = 30_000L
        )
        assertFalse(detected.suspectedPreviousRunAbort)
    }
}
