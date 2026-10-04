package com.sanogueralorenzo.androidsteam.session

import android.content.Context
import com.sanogueralorenzo.androidsteam.runtime.RuntimeArchive
import com.sanogueralorenzo.androidsteam.runtime.VerifiedDownload
import com.sanogueralorenzo.androidsteam.runtime.checkInstallationCancelled
import java.io.File
import java.nio.file.Files

internal class SteamInstaller(private val context: Context) {
    val root = File(context.filesDir, "home/.local/share/Steam")
    private val marker get() = File(root, "package/.androidsteam-installed")
    // Steam updates its own files after bootstrap. Keep the installation and all user data.
    val installed get() = marker.isFile && File(root, "steamrtarm64/steam").canExecute() &&
        File(root, "steamrtarm64/steamwebhelper").canExecute() && File(root, "linuxarm64/steamclient.so").isFile
    val protonInstalled get(): Boolean {
        val manifest = File(root, "steamapps/appmanifest_4427310.acf")
        val flags = manifest.takeIf { it.isFile && it.length() <= 64 * 1024 }?.readText()
            ?.let { Regex("\"StateFlags\"\\s+\"(\\d+)\"").find(it)?.groupValues?.get(1)?.toIntOrNull() }
        return flags != null && flags and 4 != 0 &&
            File(root, "steamapps/common/Proton Experimental (ARM64)/files/bin-arm64/wine").canExecute()
    }

    fun install(progress: (String) -> Unit) {
        if (installed) { prepareClient(); return }
        val staging = File(context.filesDir, "steam-staging")
        val archive = File(context.cacheDir, "steam.zip")
        try {
            require(context.filesDir.usableSpace >= 2_500_000_000L) { "Free at least 2.5 GB of internal storage for Steam, then retry." }
            require(!root.exists()) { "An existing Steam folder is incomplete. Preserve it before attempting a fresh installation." }
            RuntimeArchive.delete(staging)
            require(staging.mkdirs()) { "Cannot create Steam staging directory." }
            val extractor = SteamArchive(staging)
            context.assets.open("steam/packages.tsv").bufferedReader().useLines { lines ->
                lines.forEachIndexed { index, line ->
                    val (name, filename, size, hash) = line.split('\t')
                    VerifiedDownload("Steam component ${index + 1}/17 ($name)", "$CDN/$filename", size.toLong(), hash).save(archive, progress)
                    progress("Installing Steam component ${index + 1}/17…")
                    extractor.extract(archive)
                    archive.delete()
                }
            }
            extractor.finish()
            for (program in listOf("steamrtarm64/steam", "steamrtarm64/steamwebhelper")) {
                val file = File(staging, program)
                require(file.isFile && file.setExecutable(true, true)) { "Steam is missing $program." }
            }
            require(File(staging, "linuxarm64/steamclient.so").isFile) { "Steam is missing its ARM64 client library." }
            File(staging, "package").mkdirs()
            File(staging, "package/.androidsteam-installed").writeText(VERSION)
            checkInstallationCancelled()
            require(root.parentFile!!.isDirectory || root.parentFile!!.mkdirs()) { "Cannot create Steam installation directory." }
            require(staging.renameTo(root)) { "Cannot publish the Steam installation." }
            prepareClient()
        } finally {
            archive.delete()
            RuntimeArchive.delete(staging)
        }
    }

    private fun prepareClient() {
        val links = File(context.filesDir, "home/.steam").apply { mkdirs() }.toPath()
        for ((name, target) in listOf("root" to "", "steam" to "", "binarm64" to "steamrtarm64", "bin64" to "steamrtarm64", "sdkarm64" to "linuxarm64", "sdk64" to "linuxarm64")) {
            val path = links.resolve(name)
            val destination = links.relativize(File(root, target).toPath())
            if (!Files.exists(path, java.nio.file.LinkOption.NOFOLLOW_LINKS)) Files.createSymbolicLink(path, destination)
        }
        val tool = File(root, "compatibilitytools.d/androidsteam-proton")
        require(tool.isDirectory || tool.mkdirs()) { "Cannot prepare the ARM64 compatibility tool." }
        for (name in listOf("compatibilitytool.vdf", "toolmanifest.vdf", "launch")) {
            context.assets.open("steam/proton/$name").use { input -> File(tool, name).outputStream().use { input.copyTo(it) } }
        }
        require(File(tool, "launch").setExecutable(true, true)) { "Cannot prepare the ARM64 game launcher." }
    }

    companion object {
        const val VERSION = "steamdeck-stable-linuxarm64-1788652215"
        private const val CDN = "https://client-update.akamai.steamstatic.com"
    }
}
