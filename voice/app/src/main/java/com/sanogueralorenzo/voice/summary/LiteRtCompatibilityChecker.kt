package com.sanogueralorenzo.voice.summary

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.edit

data class LiteRtCompatibilityStatus(
    val modelSha: String,
    val appVersionCode: Long,
    val backendName: String,
    val healthy: Boolean,
    val failureCount: Int,
    val disabled: Boolean,
    val lastCheckedAtMs: Long,
    val lastError: String?
)

/**
 * Persists compatibility probe status keyed by model-hash + app-version + backend.
 */
class LiteRtCompatibilityChecker(context: Context) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun currentAppVersionCode(): Long {
        return try {
            val pm = appContext.packageManager
            val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageInfo(
                    appContext.packageName,
                    PackageManager.PackageInfoFlags.of(0)
                )
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(appContext.packageName, 0)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
        } catch (_: Exception) {
            0L
        }
    }

    fun hasStatus(modelSha: String, appVersionCode: Long, backendName: String): Boolean {
        val key = baseKey(modelSha, appVersionCode, backendName)
        return prefs.contains("${key}_checked")
    }

    fun statusFor(modelSha: String, appVersionCode: Long, backendName: String): LiteRtCompatibilityStatus {
        val normalizedSha = normalizeModelSha(modelSha)
        val normalizedBackend = normalizeBackendName(backendName)
        val key = baseKey(normalizedSha, appVersionCode, normalizedBackend)
        val checked = prefs.getLong("${key}_checked", 0L)
        val healthy = prefs.getBoolean("${key}_healthy", false)
        val failures = prefs.getInt("${key}_failures", 0)
        val disabled = prefs.getBoolean("${key}_disabled", false)
        val error = prefs.getString("${key}_error", null)
        return LiteRtCompatibilityStatus(
            modelSha = normalizedSha,
            appVersionCode = appVersionCode,
            backendName = normalizedBackend,
            healthy = healthy,
            failureCount = failures,
            disabled = disabled,
            lastCheckedAtMs = checked,
            lastError = error
        )
    }

    fun latestStatus(modelSha: String, appVersionCode: Long): LiteRtCompatibilityStatus? {
        val normalizedSha = normalizeModelSha(modelSha)
        val summaryKey = summaryKey(normalizedSha, appVersionCode)
        val checked = prefs.getLong("${summaryKey}_checked", 0L)
        if (checked <= 0L) return null
        val backend = prefs.getString("${summaryKey}_backend", null).orEmpty().ifBlank { "unknown" }
        val healthy = prefs.getBoolean("${summaryKey}_healthy", false)
        val failures = prefs.getInt("${summaryKey}_failures", 0)
        val disabled = prefs.getBoolean("${summaryKey}_disabled", false)
        val error = prefs.getString("${summaryKey}_error", null)
        return LiteRtCompatibilityStatus(
            modelSha = normalizedSha,
            appVersionCode = appVersionCode,
            backendName = backend,
            healthy = healthy,
            failureCount = failures,
            disabled = disabled,
            lastCheckedAtMs = checked,
            lastError = error
        )
    }

    fun recordSuccess(modelSha: String, appVersionCode: Long, backendName: String): LiteRtCompatibilityStatus {
        val normalizedSha = normalizeModelSha(modelSha)
        val normalizedBackend = normalizeBackendName(backendName)
        val key = baseKey(normalizedSha, appVersionCode, normalizedBackend)
        val now = System.currentTimeMillis()
        prefs.edit {
            putLong("${key}_checked", now)
                .putBoolean("${key}_healthy", true)
                .putInt("${key}_failures", 0)
                .putBoolean("${key}_disabled", false)
                .remove("${key}_error")
        }
        updateSummary(
            modelSha = normalizedSha,
            appVersionCode = appVersionCode,
            backendName = normalizedBackend,
            healthy = true,
            failureCount = 0,
            disabled = false,
            lastError = null,
            checkedAtMs = now
        )
        return statusFor(normalizedSha, appVersionCode, normalizedBackend)
    }

    fun recordFailure(
        modelSha: String,
        appVersionCode: Long,
        backendName: String,
        reason: String?
    ): LiteRtCompatibilityStatus {
        val normalizedSha = normalizeModelSha(modelSha)
        val normalizedBackend = normalizeBackendName(backendName)
        val key = baseKey(normalizedSha, appVersionCode, normalizedBackend)
        val previousFailures = prefs.getInt("${key}_failures", 0)
        val failures = previousFailures + 1
        val shouldDisable = reason?.startsWith("probe_empty_output") != true
        val disabled = shouldDisable && failures >= DISABLE_AFTER_FAILURES
        val now = System.currentTimeMillis()
        prefs.edit {
            putLong("${key}_checked", now)
                .putBoolean("${key}_healthy", false)
                .putInt("${key}_failures", failures)
                .putBoolean("${key}_disabled", disabled)
                .putString("${key}_error", reason?.take(MAX_REASON_LENGTH))
        }
        updateSummary(
            modelSha = normalizedSha,
            appVersionCode = appVersionCode,
            backendName = normalizedBackend,
            healthy = false,
            failureCount = failures,
            disabled = disabled,
            lastError = reason?.take(MAX_REASON_LENGTH),
            checkedAtMs = now
        )
        return statusFor(normalizedSha, appVersionCode, normalizedBackend)
    }

    fun clearForModel(modelSha: String) {
        val normalizedSha = normalizeModelSha(modelSha)
        prefs.edit {
            prefs.all.keys
                .filter { it.contains("${KEY_SEPARATOR}${normalizedSha}${KEY_SEPARATOR}") }
                .forEach { remove(it) }
        }
    }

    private fun updateSummary(
        modelSha: String,
        appVersionCode: Long,
        backendName: String,
        healthy: Boolean,
        failureCount: Int,
        disabled: Boolean,
        lastError: String?,
        checkedAtMs: Long
    ) {
        val summaryKey = summaryKey(modelSha, appVersionCode)
        prefs.edit {
            putLong("${summaryKey}_checked", checkedAtMs)
                .putString("${summaryKey}_backend", backendName)
                .putBoolean("${summaryKey}_healthy", healthy)
                .putInt("${summaryKey}_failures", failureCount)
                .putBoolean("${summaryKey}_disabled", disabled)
                .putString("${summaryKey}_error", lastError)
        }
    }

    private fun baseKey(modelSha: String, appVersionCode: Long, backendName: String): String {
        return "probe${KEY_SEPARATOR}${modelSha}${KEY_SEPARATOR}${appVersionCode}${KEY_SEPARATOR}${backendName}"
    }

    private fun summaryKey(modelSha: String, appVersionCode: Long): String {
        return "summary${KEY_SEPARATOR}${modelSha}${KEY_SEPARATOR}${appVersionCode}"
    }

    private fun normalizeModelSha(value: String): String {
        return value.trim().lowercase().ifBlank { "unknown" }
    }

    private fun normalizeBackendName(value: String): String {
        return value.trim().ifBlank { "unknown" }
    }

    private companion object {
        private const val PREFS_NAME = "litert_compatibility"
        private const val KEY_SEPARATOR = "|"
        private const val DISABLE_AFTER_FAILURES = 2
        private const val MAX_REASON_LENGTH = 220
    }
}
