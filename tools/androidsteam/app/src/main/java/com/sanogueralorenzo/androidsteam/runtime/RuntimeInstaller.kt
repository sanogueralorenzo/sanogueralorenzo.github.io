package com.sanogueralorenzo.androidsteam.runtime

import android.content.Context
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption.REPLACE_EXISTING
import org.tukaani.xz.XZInputStream

internal class RuntimeInstaller(private val context: Context) {
    private val files = context.filesDir
    private val cache = context.cacheDir
    val root = File(files, "runtime")
    val installed get() = File(root, ".androidsteam-runtime").takeIf { it.isFile }?.readText() == VERSION

    fun install(progress: (String) -> Unit) {
        if (installed) return
        val archive = File(cache, "runtime.tar.xz")
        val staging = File(files, "runtime-staging")
        val utilities = File(files, "coreutils-staging")
        try {
            require(files.usableSpace >= 850_000_000L) { "Free at least 850 MB of internal storage, then retry." }
            RuntimeArchive.delete(staging)
            require(staging.mkdirs()) { "Cannot create runtime staging directory." }
            progress("Downloading Linux runtime (98 MB)…")
            VerifiedDownload("Linux runtime", URL, ARCHIVE_SIZE, SHA256).save(archive, progress)
            checkInstallationCancelled()
            progress("Extracting Linux runtime…")
            archive.inputStream().buffered().use { input ->
                XZInputStream(input, 64 * 1024).use { RuntimeArchive.extract(it, staging, ::checkInstallationCancelled) }
            }
            progress("Preparing Linux utilities…")
            RuntimeArchive.delete(utilities)
            require(utilities.mkdirs()) { "Cannot create utilities staging directory." }
            context.assets.open("coreutils.tar.xz").use { input ->
                XZInputStream(input, 64 * 1024).use { RuntimeArchive.extract(it, utilities, ::checkInstallationCancelled) }
            }
            Files.walk(utilities.toPath()).use { paths -> paths.forEach { source ->
                checkInstallationCancelled()
                val target = staging.toPath().resolve(utilities.toPath().relativize(source))
                if (Files.isDirectory(source, java.nio.file.LinkOption.NOFOLLOW_LINKS)) Files.createDirectories(target)
                else Files.move(source, target, REPLACE_EXISTING)
            } }
            // Replace the provider, retaining only GNU utilities and their package notices.
            File(staging, "usr/bin/coreutils").delete()
            val rust = File(staging, "usr/lib/cargo/bin/coreutils")
            for (file in File(staging, "usr/bin").listFiles().orEmpty()) {
                if (Files.isSymbolicLink(file.toPath()) && file.parentFile!!.toPath().resolve(Files.readSymbolicLink(file.toPath())).normalize().startsWith(rust.toPath())) Files.delete(file.toPath())
            }
            RuntimeArchive.delete(rust)
            RuntimeArchive.delete(File(staging, "usr/share/doc/rust-coreutils"))
            require(File(staging, "usr/bin/dash").isFile && File(staging, "usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1").isFile) { "Runtime is missing its shell or loader." }
            File(staging, ".androidsteam-runtime").writeText(VERSION)
            checkInstallationCancelled()
            // User data is outside this replaceable runtime and is never removed here.
            RuntimeArchive.delete(root)
            require(staging.renameTo(root)) { "Cannot publish the installed runtime." }
        } finally {
            archive.delete()
            RuntimeArchive.delete(staging)
            RuntimeArchive.delete(utilities)
        }
    }

    companion object {
        const val VERSION = "ubuntu-resolute-arm64-20261002-gnu"
        const val URL = "https://cloud-images.ubuntu.com/minimal/releases/resolute/release-20261002/ubuntu-26.04-minimal-cloudimg-arm64-root.tar.xz"
        const val SHA256 = "7d63a5b7575e96eb0e20e07d56d3be4dd4624646d6a86b569b537c73dec4d5e9"
        const val ARCHIVE_SIZE = 102750792L
    }
}
