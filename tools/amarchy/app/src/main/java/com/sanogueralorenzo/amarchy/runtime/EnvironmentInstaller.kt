package com.sanogueralorenzo.amarchy.runtime

import android.content.Context
import java.io.File
import java.io.FilterInputStream
import java.io.InputStream
import java.security.MessageDigest
import java.util.concurrent.CancellationException
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import java.util.zip.GZIPInputStream
import android.os.SystemClock
import android.util.Log

internal class EnvironmentInstaller(private val context: Context, val root: File = File(context.filesDir, "environment")) {
    private val previous = File(root.parentFile, "${root.name}-previous")
    private val staging = File(root.parentFile, "${root.name}-staging")
    private val metadata by lazy {
        context.assets.open("environment.json").bufferedReader().use { JSONObject(it.readText()) }
    }
    init {
        if (!root.exists() && previous.exists()) check(previous.renameTo(root)) { "Could not restore your environment. Reopen Amarchy to retry." }
    }
    val installed get() = File(root, ".amarchy-environment").takeIf { it.isFile }?.readText() == metadata.getString("sha256")

    fun prepare(progress: (String, Float) -> Unit) {
        if (installed) { RuntimeArchive.delete(previous); return }
        check(context.filesDir.usableSpace >= metadata.getLong("expandedBytes") + 350_000_000L) {
            "Free some internal storage, then try again. Your workspace needs ${(metadata.getLong("expandedBytes") + 350_000_000L) / 1_000_000_000.0f} GB."
        }
        try {
            val started = SystemClock.elapsedRealtime()
            RuntimeArchive.delete(staging)
            check(staging.mkdirs()) { "Could not create your workspace. Reopen Amarchy to retry." }
            progress("Checking your environment", 0f)
            val digest = MessageDigest.getInstance("SHA-256")
            context.assets.open("environment.tar.gzip").use { input ->
                val buffer = ByteArray(128 * 1024)
                while (true) {
                    cancelled()
                    val count = input.read(buffer)
                    if (count < 0) break
                    digest.update(buffer, 0, count)
                }
            }
            check(digest.digest().joinToString("") { "%02x".format(it) } == metadata.getString("sha256")) {
                "The environment is incomplete. Reinstall the app, then try again."
            }
            val extractionStarted = SystemClock.elapsedRealtime()
            context.assets.open("environment.tar.gzip").use { asset ->
                val counter = CountedInput(asset)
                var last = -1
                GZIPInputStream(counter, 128 * 1024).use { input ->
                    RuntimeArchive.extract(input, staging) {
                        cancelled()
                        val percent = (counter.bytes * 100 / metadata.getLong("bytes")).toInt().coerceIn(0, 100)
                        if (percent != last) { last = percent; progress("Making room for your desktop", percent / 100f) }
                    }
                }
            }
            Log.i("AmarchySetup", "extractionMs=${SystemClock.elapsedRealtime() - extractionStarted}")
            for (path in listOf("dev", "proc", "sys", "tmp", "run", "root", "dev/shm")) File(staging, path).mkdirs()
            progress("Checking Linux execution", 1f)
            val process = LinuxRuntime(context, staging, 0).start(listOf("/bin/bash", "-c",
                "set -e; systemd-sysusers; pacman -Dk; ldconfig; update-ca-trust; glib-compile-schemas /usr/share/glib-2.0/schemas; " +
                    "update-desktop-database /usr/share/applications; fc-cache -f; " +
                    "printf 'amarchy-runtime-ok\\n'; uname -m"))
            val output = ProcessOutput(process, 16_384)
            try {
                check(process.waitFor(180, TimeUnit.SECONDS)) { "Your environment took too long to start. Try again." }
                val result = output.text()
                if (process.exitValue() != 0 || !result.contains("amarchy-runtime-ok") || !result.contains("aarch64"))
                    throw IllegalStateException("Linux could not start on this device. Try again after reopening Amarchy.", IllegalStateException(result))
            } finally {
                if (process.isAlive) { process.destroyForcibly(); process.waitFor(5, TimeUnit.SECONDS) }
            }
            cancelled()
            File(staging, ".amarchy-environment").writeText(metadata.getString("sha256"))
            RuntimeArchive.delete(previous)
            if (root.exists()) check(root.renameTo(previous)) { "Could not preserve your environment. Reopen Amarchy to retry." }
            if (!staging.renameTo(root)) {
                check(!previous.exists() || previous.renameTo(root)) { "Could not restore your environment. Reopen Amarchy to retry." }
                error("Could not finish setup. Try again.")
            }
            RuntimeArchive.delete(previous)
            Log.i("AmarchySetup", "preparationMs=${SystemClock.elapsedRealtime() - started}")
        } finally { RuntimeArchive.delete(staging) }
    }

    private fun cancelled() { if (Thread.currentThread().isInterrupted) throw CancellationException() }
    private class CountedInput(input: InputStream) : FilterInputStream(input) {
        var bytes = 0L
        override fun read(): Int = `in`.read().also { if (it >= 0) bytes++ }
        override fun read(buffer: ByteArray, offset: Int, length: Int): Int = `in`.read(buffer, offset, length).also { if (it > 0) bytes += it }
    }
}
