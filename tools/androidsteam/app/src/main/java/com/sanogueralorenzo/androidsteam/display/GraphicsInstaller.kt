package com.sanogueralorenzo.androidsteam.display

import android.content.Context
import com.sanogueralorenzo.androidsteam.runtime.RuntimeArchive
import com.sanogueralorenzo.androidsteam.runtime.VerifiedDownload
import com.sanogueralorenzo.androidsteam.runtime.checkInstallationCancelled
import java.io.File
import java.util.zip.ZipFile

internal class GraphicsInstaller(private val context: Context) {
    val root = File(context.filesDir, "graphics")
    private val marker get() = File(root, ".androidsteam-graphics")
    val installed get() = marker.takeIf { it.isFile }?.readText() == VERSION &&
        File(root, "android/libvulkan_freedreno.so").length() == ANDROID_BYTES &&
        File(root, "linux/libvulkan_freedreno.so").length() == LINUX_BYTES &&
        File(root, "linux/freedreno_icd.aarch64.json").isFile

    fun install(progress: (String) -> Unit) {
        if (installed) return
        val staging = File(context.filesDir, "graphics-staging")
        val archive = File(context.cacheDir, "graphics.zip")
        try {
            require(context.filesDir.usableSpace >= 80_000_000L) { "Free at least 80 MB of internal storage for graphics, then retry." }
            RuntimeArchive.delete(staging)
            require(staging.mkdirs()) { "Cannot create graphics staging directory." }
            installDriver(ANDROID, ANDROID_BYTES, File(staging, "android"), archive, progress)
            installDriver(LINUX, LINUX_BYTES, File(staging, "linux"), archive, progress)
            File(staging, "linux/freedreno_icd.aarch64.json").writeText("""{"file_format_version":"1.0.0","ICD":{"library_path":"./libvulkan_freedreno.so","api_version":"1.1.274"}}""")
            File(staging, ".androidsteam-graphics").writeText(VERSION)
            checkInstallationCancelled()
            RuntimeArchive.delete(root)
            require(staging.renameTo(root)) { "Cannot publish the graphics installation." }
        } finally {
            archive.delete()
            RuntimeArchive.delete(staging)
        }
    }

    private fun installDriver(download: VerifiedDownload, bytes: Long, directory: File, archive: File, progress: (String) -> Unit) {
        download.save(archive, progress)
        checkInstallationCancelled()
        require(directory.mkdirs()) { "Cannot create driver directory." }
        ZipFile(archive).use { zip ->
            val metadata = zip.getEntry("meta.json") ?: error("${download.name} is missing its metadata.")
            require(metadata.size in 1..4096) { "Driver metadata exceeds its expected size." }
            zip.getInputStream(metadata).use { input -> File(directory, "meta.json").outputStream().use { input.copyTo(it) } }
            val entry = zip.getEntry("libvulkan_freedreno.so") ?: error("${download.name} is missing its library.")
            require(entry.size == bytes && !entry.isDirectory) { "${download.name} has an unexpected library size." }
            val library = File(directory, "libvulkan_freedreno.so")
            zip.getInputStream(entry).use { input -> library.outputStream().use { output ->
                val buffer = ByteArray(64 * 1024)
                var written = 0L
                while (true) {
                    checkInstallationCancelled()
                    val read = input.read(buffer)
                    if (read < 0) break
                    written += read
                    require(written <= bytes) { "Driver library exceeds its expected size." }
                    output.write(buffer, 0, read)
                }
                require(written == bytes) { "Driver library is incomplete." }
            } }
        }
    }

    companion object {
        const val VERSION = "arch-turnip-v26.3.0-20261003-r4-libraries-2"
        private const val BASE = "https://github.com/The412Banner/Banners-Turnip/releases/download/v26.3.0-20261003-r4/Turnip-v26.3.0-20261003-r4"
        private const val ANDROID_BYTES = 13904152L
        private const val LINUX_BYTES = 15351584L
        private val ANDROID = VerifiedDownload("Android graphics driver", "$BASE.zip", 2638581L, "355c2d7f9250ee90abb97ef4928c9b6cb3f80830cd26d4ad7c5ca63936a24238")
        private val LINUX = VerifiedDownload("Linux graphics driver", "$BASE-Linux.zip", 3216409L, "9d51b9956cd39f05b4e44fc7006a016bcc69c9dd8a1931662330cbbc27478202")
    }
}
