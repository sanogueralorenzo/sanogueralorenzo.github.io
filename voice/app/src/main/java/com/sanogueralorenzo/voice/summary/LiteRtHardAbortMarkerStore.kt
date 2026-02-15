package com.sanogueralorenzo.voice.summary

import android.content.Context

data class LiteRtHardAbortStatus(
    val suspectedPreviousRunAbort: Boolean,
    val suspectedAbortCount: Int,
    val lastDetectedAtMs: Long
)

/**
 * Persists a minimal in-flight marker around native LiteRT generation.
 *
 * If process dies mid-generation, marker remains set. On next startup we treat a stale marker
 * as a suspected native abort and clear it.
 */
class LiteRtHardAbortMarkerStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun detectAndConsumeStaleMarker(
        staleAfterMs: Long = DEFAULT_STALE_AFTER_MS,
        nowMs: Long = System.currentTimeMillis()
    ): LiteRtHardAbortStatus {
        val active = prefs.getBoolean(KEY_ACTIVE, false)
        val startedAt = prefs.getLong(KEY_STARTED_AT_MS, 0L)
        var suspectedCount = prefs.getInt(KEY_SUSPECTED_COUNT, 0)
        var suspected = false
        var detectedAt = prefs.getLong(KEY_LAST_DETECTED_AT_MS, 0L)
        if (active && startedAt > 0L && (nowMs - startedAt) >= staleAfterMs) {
            suspected = true
            suspectedCount += 1
            detectedAt = nowMs
            prefs.edit()
                .putInt(KEY_SUSPECTED_COUNT, suspectedCount)
                .putLong(KEY_LAST_DETECTED_AT_MS, detectedAt)
                .putBoolean(KEY_ACTIVE, false)
                .putLong(KEY_STARTED_AT_MS, 0L)
                .apply()
        }
        return LiteRtHardAbortStatus(
            suspectedPreviousRunAbort = suspected,
            suspectedAbortCount = suspectedCount,
            lastDetectedAtMs = detectedAt
        )
    }

    fun markOperationStart(nowMs: Long = System.currentTimeMillis()) {
        prefs.edit()
            .putBoolean(KEY_ACTIVE, true)
            .putLong(KEY_STARTED_AT_MS, nowMs)
            .apply()
    }

    fun clearOperationMarker() {
        prefs.edit()
            .putBoolean(KEY_ACTIVE, false)
            .putLong(KEY_STARTED_AT_MS, 0L)
            .apply()
    }

    fun currentStatus(): LiteRtHardAbortStatus {
        return LiteRtHardAbortStatus(
            suspectedPreviousRunAbort = false,
            suspectedAbortCount = prefs.getInt(KEY_SUSPECTED_COUNT, 0),
            lastDetectedAtMs = prefs.getLong(KEY_LAST_DETECTED_AT_MS, 0L)
        )
    }

    private companion object {
        private const val PREFS_NAME = "litert_hard_abort_marker"
        private const val KEY_ACTIVE = "active"
        private const val KEY_STARTED_AT_MS = "started_at_ms"
        private const val KEY_SUSPECTED_COUNT = "suspected_count"
        private const val KEY_LAST_DETECTED_AT_MS = "last_detected_at_ms"
        private const val DEFAULT_STALE_AFTER_MS = 10_000L
    }
}
