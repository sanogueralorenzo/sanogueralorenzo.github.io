package com.sanogueralorenzo.androiddeck.runtime

import java.io.File
import java.net.URL
import javax.net.ssl.HttpsURLConnection
import java.security.MessageDigest
import java.util.concurrent.CancellationException
import org.tukaani.xz.XZInputStream

internal class RuntimeInstaller(private val files: File, private val cache: File) {
    val root = File(files, "runtime")
    val installed get() = File(root, ".androiddeck-runtime").takeIf { it.isFile }?.readText() == VERSION

    fun install(progress: (String) -> Unit) {
        if (installed) return
        val archive = File(cache, "runtime.tar.xz")
        val staging = File(files, "runtime-staging")
        try {
            require(files.usableSpace >= 650_000_000L) { "Free at least 650 MB of internal storage, then retry." }
            RuntimeArchive.delete(staging)
            require(staging.mkdirs()) { "Cannot create runtime staging directory." }
            progress("Downloading Linux runtime (78 MB)…")
            download(archive, progress)
            checkCancelled()
            progress("Extracting Linux runtime…")
            archive.inputStream().buffered().use { input ->
                XZInputStream(input, 64 * 1024).use { RuntimeArchive.extract(it, staging, ::checkCancelled) }
            }
            require(File(staging, "usr/bin/dash").isFile && File(staging, "usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1").isFile) { "Runtime is missing its shell or loader." }
            File(staging, ".androiddeck-runtime").writeText(VERSION)
            checkCancelled()
            // User data is outside this replaceable runtime and is never removed here.
            RuntimeArchive.delete(root)
            require(staging.renameTo(root)) { "Cannot publish the installed runtime." }
        } finally {
            archive.delete()
            RuntimeArchive.delete(staging)
        }
    }

    private fun download(archive: File, progress: (String) -> Unit) {
        val connection = URL(URL).openConnection() as HttpsURLConnection
        connection.connectTimeout = 15_000
        connection.readTimeout = 30_000
        val digest = MessageDigest.getInstance("SHA-256")
        try {
            require(connection.responseCode == 200) { "Runtime download failed (HTTP ${connection.responseCode}). Retry when connected." }
            var bytes = 0L
            var lastPercent = -1
            connection.inputStream.use { input ->
                archive.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        checkCancelled()
                        val read = input.read(buffer)
                        if (read < 0) break
                        bytes += read
                        require(bytes <= ARCHIVE_SIZE) { "Runtime download is larger than expected." }
                        digest.update(buffer, 0, read)
                        output.write(buffer, 0, read)
                        val percent = (bytes * 100 / ARCHIVE_SIZE).toInt()
                        if (percent != lastPercent) { progress("Downloading Linux runtime… $percent%"); lastPercent = percent }
                    }
                }
            }
            require(bytes == ARCHIVE_SIZE && digest.digest().joinToString("") { "%02x".format(it) } == SHA256) { "Runtime verification failed. Retry the download." }
        } finally { connection.disconnect() }
    }

    private fun checkCancelled() {
        if (Thread.currentThread().isInterrupted) throw CancellationException("Runtime installation cancelled.")
    }

    companion object {
        const val VERSION = "ubuntu-noble-arm64-20261001"
        const val URL = "https://cloud-images.ubuntu.com/minimal/releases/noble/release-20261001/ubuntu-24.04-minimal-cloudimg-arm64-root.tar.xz"
        const val SHA256 = "eadd5f1664ea508c785aa8c01a021cac900c24a3d7c0f0f0c4679d7e6aced2d9"
        const val ARCHIVE_SIZE = 81662644L
    }
}
