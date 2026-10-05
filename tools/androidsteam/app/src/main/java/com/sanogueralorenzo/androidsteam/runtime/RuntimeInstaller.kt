package com.sanogueralorenzo.androidsteam.runtime

import android.content.Context
import java.io.File
import org.tukaani.xz.XZInputStream
import java.util.concurrent.TimeUnit

internal class RuntimeInstaller(private val context: Context, val root: File = File(context.filesDir, "runtime")) {
    private val files = context.filesDir
    private val cache = context.cacheDir
    private val previous = File(root.parentFile, "${root.name}-previous")
    init {
        if (!root.exists() && previous.exists()) {
            require(previous.renameTo(root)) { "Cannot recover the previous Linux runtime." }
        }
    }
    val installed get() = File(root, ".androidsteam-runtime").takeIf { it.isFile }?.readText() == VERSION

    fun install(progress: (String) -> Unit) {
        if (installed) {
            // Finish cleanup if the app stopped after publishing the new root.
            RuntimeArchive.delete(previous)
            return
        }
        val archive = File(cache, "runtime.tar.xz")
        try {
            require(files.usableSpace >= 1_500_000_000L) { "Free at least 1.5 GB of internal storage, then retry." }
            progress("Downloading the pinned Arch ARM runtime…")
            VerifiedDownload("Linux runtime", URL, ARCHIVE_SIZE, SHA256).save(archive, progress)
            prepare(archive, progress)
        } finally { archive.delete() }
    }

    internal fun prepare(archive: File, progress: (String) -> Unit) {
        val staging = File(root.parentFile, "${root.name}-staging")
        try {
            require(files.usableSpace >= 1_500_000_000L) { "Free at least 1.5 GB of internal storage, then retry." }
            checkInstallationCancelled()
            RuntimeArchive.delete(staging)
            require(staging.mkdirs()) { "Cannot create runtime staging directory." }
            progress("Extracting Linux runtime…")
            archive.inputStream().buffered().use { input ->
                XZInputStream(input, 64 * 1024).use { RuntimeArchive.extract(it, staging, ::checkInstallationCancelled) }
            }
            require(File(staging, "usr/bin/dash").isFile && File(staging, "usr/lib/ld-linux-aarch64.so.1").isFile) { "Runtime is missing its shell or loader." }
            progress("Preparing Linux certificates and caches…")
            val check = LinuxRuntime(context, staging).start(listOf("/bin/sh", "-c",
                "set -e; update-ca-trust; glib-compile-schemas /usr/share/glib-2.0/schemas; " +
                "gdk-pixbuf-query-loaders --update-cache; fc-cache -f; ldconfig; " +
                "printf 'Linux runtime ready\\n'; ldd --version; uname -m; python3 --version"))
            try {
                require(check.waitFor(60, TimeUnit.SECONDS)) { "The new Linux runtime did not finish its startup check." }
                val output = check.inputStream.bufferedReader().readText()
                require(check.exitValue() == 0 && output.contains("Linux runtime ready") && output.contains("aarch64")) {
                    "The new Linux runtime failed its startup check.\n$output"
                }
            } finally { check.destroyForcibly() }
            File(staging, ".androidsteam-runtime").writeText(VERSION)
            checkInstallationCancelled()
            // Preserve home and restore the old runtime if publication fails.
            // init also recovers a process interruption between the two moves.
            RuntimeArchive.delete(previous)
            if (root.exists()) require(root.renameTo(previous)) { "Cannot preserve the previous Linux runtime." }
            if (!staging.renameTo(root)) {
                require(!previous.exists() || previous.renameTo(root)) { "Cannot restore the previous Linux runtime." }
                error("Cannot publish the installed runtime.")
            }
            RuntimeArchive.delete(previous)
        } finally {
            RuntimeArchive.delete(staging)
        }
    }

    companion object {
        const val VERSION = "arch-arm64-20261005-1"
        const val URL = "https://github.com/sanogueralorenzo/sanogueralorenzo.github.io/releases/download/androidsteam-runtime-20261005-1/runtime.tar.xz"
        const val SHA256 = "5d9571fd3e463a39dc33f052e693f6dc3069508eb5969cde2f7d8908d1115318"
        const val ARCHIVE_SIZE = 99009976L
    }
}
