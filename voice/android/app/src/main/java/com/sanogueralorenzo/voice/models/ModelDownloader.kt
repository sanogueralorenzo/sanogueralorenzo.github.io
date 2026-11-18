package com.sanogueralorenzo.voice.models

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.net.UnknownHostException
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * Downloads model files sequentially on a dedicated background executor and verifies integrity
 * using expected size/hash when provided in [ModelSpec].
 */
sealed interface ModelDownloadResult {
    data object Success : ModelDownloadResult
    data object AlreadyAvailable : ModelDownloadResult
    data class HttpError(val code: Int) : ModelDownloadResult
    data class HashMismatch(val expected: String, val actual: String) : ModelDownloadResult
    data class SizeMismatch(val expected: Long, val actual: Long) : ModelDownloadResult
    data class NetworkError(val reason: String? = null) : ModelDownloadResult
    data class StorageError(val reason: String? = null) : ModelDownloadResult
    data class UnknownError(val reason: String? = null) : ModelDownloadResult
    data object InvalidSpec : ModelDownloadResult
}

class ModelDownloader(private val context: Context) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()

    fun download(
        spec: ModelSpec,
        force: Boolean = false,
        onProgress: (Int) -> Unit,
        onComplete: (ModelDownloadResult) -> Unit
    ) {
        if (ModelUrlResolver.candidateUrls(spec).isEmpty()) {
            mainHandler.post { onComplete(ModelDownloadResult.InvalidSpec) }
            return
        }
        executor.execute {
            val result = downloadInternal(spec, force, onProgress)
            mainHandler.post { onComplete(result) }
        }
    }

    fun shutdown() {
        executor.shutdownNow()
    }

    private fun downloadInternal(
        spec: ModelSpec,
        force: Boolean,
        onProgress: (Int) -> Unit
    ): ModelDownloadResult {
        // Treat already-available (asset or verified file) as success from the UI standpoint.
        val alreadyReady = !force && (ModelStore.ensureModelFile(context, spec) != null)
        if (alreadyReady) return ModelDownloadResult.AlreadyAvailable

        val candidateUrls = ModelUrlResolver.candidateUrls(spec)
        if (candidateUrls.isEmpty()) return ModelDownloadResult.InvalidSpec

        var lastFailure: ModelDownloadResult = ModelDownloadResult.InvalidSpec
        for (sourceUrl in candidateUrls) {
            val result = downloadFromUrl(spec, sourceUrl, onProgress)
            if (result is ModelDownloadResult.Success) {
                return result
            }
            lastFailure = result
        }
        return lastFailure
    }

    private fun downloadFromUrl(
        spec: ModelSpec,
        sourceUrl: String,
        onProgress: (Int) -> Unit
    ): ModelDownloadResult {
        val target = ModelStore.modelFile(context, spec)
        target.parentFile?.mkdirs()
        val temp = File(target.parentFile, "${spec.fileName}.download_tmp")
        if (temp.exists()) temp.delete()

        var connection: HttpURLConnection? = null
        return try {
            val url = URL(sourceUrl)
            connection = (url.openConnection() as HttpURLConnection).apply {
                connectTimeout = CONNECT_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                instanceFollowRedirects = true
            }

            val responseCode = connection.responseCode
            if (responseCode != HttpURLConnection.HTTP_OK) {
                return ModelDownloadResult.HttpError(responseCode)
            }

            val contentLength = connection.contentLengthLong.takeIf { it > 0L } ?: -1L
            val expectedBytes = when {
                spec.sizeBytes > 0L -> spec.sizeBytes
                contentLength > 0L -> contentLength
                else -> -1L
            }

            val digest = if (spec.sha256.isNotBlank()) MessageDigest.getInstance("SHA-256") else null
            var lastPercent = -1
            var lastProgressAtMs = 0L
            var downloaded = 0L

            connection.inputStream.use { input ->
                FileOutputStream(temp).use { output ->
                    val buffer = ByteArray(DOWNLOAD_BUFFER_BYTES)
                    var read: Int
                    while (input.read(buffer).also { read = it } != -1) {
                        output.write(buffer, 0, read)
                        digest?.update(buffer, 0, read)
                        downloaded += read.toLong()

                        if (expectedBytes > 0L) {
                            val percent = (downloaded * 100L / expectedBytes).toInt().coerceIn(0, 100)
                            val now = SystemClock.uptimeMillis()
                            if (percent != lastPercent && (now - lastProgressAtMs) >= PROGRESS_THROTTLE_MS) {
                                lastPercent = percent
                                lastProgressAtMs = now
                                mainHandler.post { onProgress(percent) }
                            }
                        }
                    }
                }
            }

            if (contentLength > 0L && downloaded != contentLength) {
                temp.delete()
                return ModelDownloadResult.SizeMismatch(expected = contentLength, actual = downloaded)
            }
            if (spec.sizeBytes > 0L && downloaded != spec.sizeBytes) {
                temp.delete()
                return ModelDownloadResult.SizeMismatch(expected = spec.sizeBytes, actual = downloaded)
            }
            if (expectedBytes > 0L) {
                mainHandler.post { onProgress(100) }
            }

            if (spec.sha256.isNotBlank()) {
                val actual = digest?.digest()?.joinToString("") { "%02x".format(it) } ?: ""
                if (!actual.equals(spec.sha256, ignoreCase = true)) {
                    temp.delete()
                    return ModelDownloadResult.HashMismatch(expected = spec.sha256, actual = actual)
                }
            }

            if (target.exists()) target.delete()
            if (!moveAtomically(temp, target)) {
                temp.delete()
                return ModelDownloadResult.StorageError("failed to move temp file")
            }
            ModelStore.markModelVerified(target, spec)
            ModelDownloadResult.Success
        } catch (e: UnknownHostException) {
            temp.delete()
            ModelDownloadResult.NetworkError(e.message)
        } catch (e: SocketTimeoutException) {
            temp.delete()
            ModelDownloadResult.NetworkError(e.message)
        } catch (e: IOException) {
            temp.delete()
            ModelDownloadResult.NetworkError(e.message)
        } catch (e: SecurityException) {
            temp.delete()
            ModelDownloadResult.StorageError(e.message)
        } catch (e: Exception) {
            temp.delete()
            ModelDownloadResult.UnknownError(e.message)
        } finally {
            connection?.disconnect()
        }
    }

    private fun moveAtomically(from: File, to: File): Boolean {
        if (from.renameTo(to)) {
            return true
        }
        return try {
            from.copyTo(to, overwrite = true)
            from.delete()
            true
        } catch (_: Exception) {
            false
        }
    }

    private companion object {
        private const val CONNECT_TIMEOUT_MS = 15_000
        private const val READ_TIMEOUT_MS = 20_000
        private const val DOWNLOAD_BUFFER_BYTES = 8 * 1024
        private const val PROGRESS_THROTTLE_MS = 150L
    }
}
