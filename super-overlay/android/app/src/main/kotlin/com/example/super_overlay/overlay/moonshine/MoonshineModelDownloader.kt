package com.example.super_overlay.overlay.moonshine

import android.content.Context
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL

sealed class MoonshineDownloadResult {
    data object Success : MoonshineDownloadResult()
    data class Failure(val reason: String) : MoonshineDownloadResult()
}

class MoonshineModelDownloader(private val context: Context) {
    fun downloadMissingModels(): MoonshineDownloadResult {
        for (spec in MoonshineModelCatalog.mediumStreamingSpecs) {
            if (MoonshineModelStore.isModelPresent(context, spec)) {
                continue
            }
            val file = MoonshineModelStore.modelFile(context, spec)
            file.parentFile?.mkdirs()
            val temp = File(file.parentFile, "${file.name}.download_tmp")
            if (temp.exists()) {
                temp.delete()
            }

            val downloaded = downloadFile(spec.url, temp)
            if (!downloaded) {
                temp.delete()
                return MoonshineDownloadResult.Failure("Download failed for ${spec.fileName}")
            }

            if (spec.sizeBytes > 0L && temp.length() != spec.sizeBytes) {
                temp.delete()
                return MoonshineDownloadResult.Failure(
                    "Unexpected size for ${spec.fileName}: ${temp.length()}"
                )
            }

            if (file.exists()) {
                file.delete()
            }
            val moved = temp.renameTo(file) || runCatching {
                temp.copyTo(file, overwrite = true)
                temp.delete()
                true
            }.getOrDefault(false)
            if (!moved) {
                temp.delete()
                return MoonshineDownloadResult.Failure("Could not move ${spec.fileName}")
            }
        }
        return MoonshineDownloadResult.Success
    }

    private fun downloadFile(urlString: String, target: File): Boolean {
        var connection: HttpURLConnection? = null
        return try {
            connection = (URL(urlString).openConnection() as HttpURLConnection).apply {
                connectTimeout = CONNECT_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                instanceFollowRedirects = true
            }
            if (connection.responseCode != HttpURLConnection.HTTP_OK) {
                return false
            }
            connection.inputStream.use { input ->
                FileOutputStream(target).use { output ->
                    val buffer = ByteArray(DOWNLOAD_BUFFER_BYTES)
                    var read = input.read(buffer)
                    while (read != -1) {
                        output.write(buffer, 0, read)
                        read = input.read(buffer)
                    }
                    output.flush()
                }
            }
            true
        } catch (_: SocketTimeoutException) {
            false
        } catch (_: Exception) {
            false
        } finally {
            connection?.disconnect()
        }
    }

    private companion object {
        private const val CONNECT_TIMEOUT_MS = 15_000
        private const val READ_TIMEOUT_MS = 30_000
        private const val DOWNLOAD_BUFFER_BYTES = 8 * 1024
    }
}
