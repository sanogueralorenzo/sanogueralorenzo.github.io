package com.sanogueralorenzo.androidsteam.session

import android.content.Context
import com.sanogueralorenzo.androidsteam.runtime.RuntimeArchive
import com.sanogueralorenzo.androidsteam.runtime.checkInstallationCancelled
import java.io.File
import org.tukaani.xz.XZInputStream

internal class SessionComponents(private val context: Context) {
    val root = File(context.filesDir, "session-components")
    val installed get() = File(root, ".androidsteam-components").takeIf { it.isFile }?.readText() == VERSION &&
        complete(root)

    private fun complete(directory: File) = File(directory, "usr/games/gamescope").canExecute() &&
        File(directory, "usr/bin/Xwayland").canExecute() &&
        File(directory, "usr/lib/aarch64-linux-gnu/libdeck-drm.so").isFile &&
        File(directory, "usr/lib/aarch64-linux-gnu/libdeck-robust.so").isFile &&
        File(directory, "usr/lib/aarch64-linux-gnu/libdeck-ports.so").isFile &&
        File(directory, "usr/bin/steam-socket-peer").canExecute()

    fun install(progress: (String) -> Unit) {
        if (installed) return
        val staging = File(context.filesDir, "session-components-staging")
        try {
            require(context.filesDir.usableSpace >= 450_000_000L) { "Free at least 450 MB for Steam session components, then retry." }
            RuntimeArchive.delete(staging)
            require(staging.mkdirs()) { "Cannot create session components staging directory." }
            progress("Installing Steam session components…")
            context.assets.open("session-components.tar.xz").use { input ->
                XZInputStream(input, 64 * 1024).use { RuntimeArchive.extract(it, staging, ::checkInstallationCancelled) }
            }
            require(complete(staging)) { "Session components are missing Gamescope, XWayland, or a session adapter." }
            File(staging, ".androidsteam-components").writeText(VERSION)
            checkInstallationCancelled()
            RuntimeArchive.delete(root)
            require(staging.renameTo(root)) { "Cannot publish session components." }
        } finally { RuntimeArchive.delete(staging) }
    }

    companion object { const val VERSION = "resolute-gamescope-3.16.20-components-9" }
}
