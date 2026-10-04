package com.sanogueralorenzo.androiddeck.runtime

import java.io.File
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
            VerifiedDownload("Linux runtime", URL, ARCHIVE_SIZE, SHA256).save(archive, progress)
            checkInstallationCancelled()
            progress("Extracting Linux runtime…")
            archive.inputStream().buffered().use { input ->
                XZInputStream(input, 64 * 1024).use { RuntimeArchive.extract(it, staging, ::checkInstallationCancelled) }
            }
            require(File(staging, "usr/bin/dash").isFile && File(staging, "usr/lib/aarch64-linux-gnu/ld-linux-aarch64.so.1").isFile) { "Runtime is missing its shell or loader." }
            File(staging, ".androiddeck-runtime").writeText(VERSION)
            checkInstallationCancelled()
            // User data is outside this replaceable runtime and is never removed here.
            RuntimeArchive.delete(root)
            require(staging.renameTo(root)) { "Cannot publish the installed runtime." }
        } finally {
            archive.delete()
            RuntimeArchive.delete(staging)
        }
    }

    companion object {
        const val VERSION = "ubuntu-noble-arm64-20261001"
        const val URL = "https://cloud-images.ubuntu.com/minimal/releases/noble/release-20261001/ubuntu-24.04-minimal-cloudimg-arm64-root.tar.xz"
        const val SHA256 = "eadd5f1664ea508c785aa8c01a021cac900c24a3d7c0f0f0c4679d7e6aced2d9"
        const val ARCHIVE_SIZE = 81662644L
    }
}
