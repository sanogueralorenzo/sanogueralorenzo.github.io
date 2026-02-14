package com.sanogueralorenzo.voice.asr

import android.content.Context
import androidx.core.content.edit

data class AsrLastRunStatus(
    val engineUsed: AsrEngine,
    val fallbackFrom: AsrEngine?,
    val reason: String?,
    val timestampMs: Long
)

/**
 * Persists lightweight ASR runtime diagnostics for the setup screen.
 */
class AsrRuntimeStatusStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun recordRun(engineUsed: AsrEngine, fallbackFrom: AsrEngine? = null, reason: String? = null) {
        val now = System.currentTimeMillis()
        prefs.edit {
            putString(KEY_LAST_ENGINE_USED, engineUsed.id)
                .putString(KEY_LAST_FALLBACK_FROM, fallbackFrom?.id)
                .putString(KEY_LAST_REASON, reason)
                .putLong(KEY_LAST_RUN_TS_MS, now)
        }
    }

    fun lastRun(): AsrLastRunStatus? {
        val timestamp = prefs.getLong(KEY_LAST_RUN_TS_MS, 0L)
        if (timestamp <= 0L) return null
        val engineUsed = AsrEngine.fromId(prefs.getString(KEY_LAST_ENGINE_USED, null))
        val fallbackFrom = prefs.getString(KEY_LAST_FALLBACK_FROM, null)?.let { AsrEngine.fromId(it) }
        val reason = prefs.getString(KEY_LAST_REASON, null)
        return AsrLastRunStatus(
            engineUsed = engineUsed,
            fallbackFrom = fallbackFrom,
            reason = reason,
            timestampMs = timestamp
        )
    }

    companion object {
        private const val PREFS_NAME = "voice_asr_runtime_status_prefs"
        private const val KEY_LAST_ENGINE_USED = "last_engine_used"
        private const val KEY_LAST_FALLBACK_FROM = "last_fallback_from"
        private const val KEY_LAST_REASON = "last_reason"
        private const val KEY_LAST_RUN_TS_MS = "last_run_ts_ms"
    }
}
