package com.sanogueralorenzo.androiddeck.runtime

import java.io.File
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.CancellationException
import javax.net.ssl.HttpsURLConnection

internal data class VerifiedDownload(val name: String, val url: String, val size: Long, val sha256: String) {
    fun save(destination: File, progress: (String) -> Unit) {
        checkInstallationCancelled()
        val connection = URL(url).openConnection() as HttpsURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        val digest = MessageDigest.getInstance("SHA-256")
        try {
            require(connection.responseCode == 200) { "$name download failed (HTTP ${connection.responseCode}). Retry when connected." }
            var bytes = 0L
            var lastPercent = -1
            connection.inputStream.use { input ->
                destination.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        checkInstallationCancelled()
                        val read = input.read(buffer)
                        if (read < 0) break
                        bytes += read
                        require(bytes <= size) { "$name download is larger than expected." }
                        digest.update(buffer, 0, read)
                        output.write(buffer, 0, read)
                        val percent = (bytes * 100 / size).toInt()
                        if (percent != lastPercent) { progress("Downloading $name… $percent%"); lastPercent = percent }
                    }
                }
            }
            require(bytes == size && digest.digest().joinToString("") { "%02x".format(it) } == sha256) { "$name verification failed. Retry the download." }
        } finally { connection.disconnect() }
    }
}

internal fun checkInstallationCancelled() {
    if (Thread.currentThread().isInterrupted) throw CancellationException("Installation cancelled.")
}
