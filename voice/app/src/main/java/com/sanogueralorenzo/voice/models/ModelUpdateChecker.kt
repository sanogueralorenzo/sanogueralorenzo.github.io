package com.sanogueralorenzo.voice.models

import android.content.Context
import dev.zacsweers.metro.AppScope
import dev.zacsweers.metro.Inject
import dev.zacsweers.metro.SingleIn
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit

/**
 * Checks whether remote model files changed by comparing persisted remote metadata
 * (ETag/Last-Modified/Content-Length) against current upstream values.
 *
 * This works with any HTTP(s) source used in [ModelSpec.url], including GitHub raw,
 * Hugging Face, or official vendor hosts.
 */
@Inject
@SingleIn(AppScope::class)
class ModelUpdateChecker(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val appContext = context.applicationContext

    data class RemoteSnapshot(
        val etag: String?,
        val lastModified: String?,
        val contentLength: Long
    ) {
        fun sameAs(other: RemoteSnapshot): Boolean {
            return normalize(etag) == normalize(other.etag) &&
                normalize(lastModified) == normalize(other.lastModified) &&
                contentLength == other.contentLength
        }
    }

    data class UpdateCandidate(
        val spec: ModelSpec,
        val snapshot: RemoteSnapshot?
    )

    sealed interface CheckResult {
        data class UpToDate(val checkedCount: Int) : CheckResult
        data class UpdatesAvailable(val updates: List<UpdateCandidate>) : CheckResult
        data class Unreachable(val checkedCount: Int) : CheckResult
    }

    fun check(specs: List<ModelSpec>): CheckResult {
        val updates = ArrayList<UpdateCandidate>()
        var remotelyChecked = 0

        for (spec in specs) {
            val localReady = ModelStore.isModelReadyStrict(appContext, spec)
            val remote = fetchRemoteSnapshot(spec)
            if (remote != null) {
                remotelyChecked += 1
            }

            if (!localReady) {
                updates.add(UpdateCandidate(spec = spec, snapshot = remote))
                continue
            }

            if (remote == null) {
                continue
            }

            val cached = readCachedSnapshot(spec.id)
            if (cached == null) {
                cacheSnapshot(spec.id, remote)
                continue
            }

            if (!cached.sameAs(remote)) {
                updates.add(UpdateCandidate(spec = spec, snapshot = remote))
            }
        }

        if (updates.isNotEmpty()) {
            return CheckResult.UpdatesAvailable(updates)
        }
        if (remotelyChecked == 0) {
            return CheckResult.Unreachable(checkedCount = 0)
        }
        return CheckResult.UpToDate(checkedCount = remotelyChecked)
    }

    fun markApplied(candidate: UpdateCandidate) {
        candidate.snapshot?.let { cacheSnapshot(candidate.spec.id, it) }
    }

    private fun fetchRemoteSnapshot(spec: ModelSpec): RemoteSnapshot? {
        val candidates = ModelUrlResolver.candidateUrls(spec)
        if (candidates.isEmpty()) return null
        for (url in candidates) {
            val snapshot = headSnapshot(url) ?: rangeSnapshot(url)
            if (snapshot != null) return snapshot
        }
        return null
    }

    private fun headSnapshot(url: String): RemoteSnapshot? {
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "HEAD"
                connectTimeout = CONNECT_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                instanceFollowRedirects = true
            }
            val code = connection.responseCode
            if (code !in 200..399) return null
            snapshotFrom(connection)
        } catch (_: UnknownHostException) {
            null
        } catch (_: IOException) {
            null
        } catch (_: Exception) {
            null
        } finally {
            connection?.disconnect()
        }
    }

    private fun rangeSnapshot(url: String): RemoteSnapshot? {
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = CONNECT_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                instanceFollowRedirects = true
                setRequestProperty("Range", "bytes=0-0")
            }
            val code = connection.responseCode
            if (code !in 200..299 && code != 206) return null
            // Ensure request is executed then discard.
            runCatching { connection.inputStream.use { it.read() } }
            snapshotFrom(connection)
        } catch (_: UnknownHostException) {
            null
        } catch (_: IOException) {
            null
        } catch (_: Exception) {
            null
        } finally {
            connection?.disconnect()
        }
    }

    private fun snapshotFrom(connection: HttpURLConnection): RemoteSnapshot? {
        val etag = connection.getHeaderField("ETag")
        val lastModified = connection.getHeaderField("Last-Modified")
        val contentLength = connection.contentLengthLong.takeIf { it > 0L } ?: -1L
        if (etag.isNullOrBlank() && lastModified.isNullOrBlank() && contentLength <= 0L) {
            return null
        }
        return RemoteSnapshot(
            etag = etag,
            lastModified = lastModified,
            contentLength = contentLength
        )
    }

    private fun readCachedSnapshot(id: String): RemoteSnapshot? {
        val etag = prefs.getString(key(id, "etag"), null)
        val lastModified = prefs.getString(key(id, "lm"), null)
        val contentLength = prefs.getLong(key(id, "cl"), -1L)
        if (etag.isNullOrBlank() && lastModified.isNullOrBlank() && contentLength <= 0L) {
            return null
        }
        return RemoteSnapshot(
            etag = etag,
            lastModified = lastModified,
            contentLength = contentLength
        )
    }

    private fun cacheSnapshot(id: String, snapshot: RemoteSnapshot) {
        prefs.edit()
            .putString(key(id, "etag"), normalize(snapshot.etag))
            .putString(key(id, "lm"), normalize(snapshot.lastModified))
            .putLong(key(id, "cl"), snapshot.contentLength)
            .apply()
    }

    private fun key(id: String, suffix: String): String = "model.$id.$suffix"

    private companion object {
        private const val PREFS_NAME = "model_update_checker"
        private val CONNECT_TIMEOUT_MS = TimeUnit.SECONDS.toMillis(10).toInt()
        private val READ_TIMEOUT_MS = TimeUnit.SECONDS.toMillis(12).toInt()

        private fun normalize(value: String?): String? {
            return value
                ?.trim()
                ?.trim('"')
                ?.ifBlank { null }
        }
    }
}
