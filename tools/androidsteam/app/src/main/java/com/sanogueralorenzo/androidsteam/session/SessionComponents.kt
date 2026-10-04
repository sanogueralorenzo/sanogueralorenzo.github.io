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

    private fun complete(directory: File) = File(directory, "usr/lib/libdeck-drm.so").isFile &&
        File(directory, "usr/lib/libdeck-robust.so").isFile &&
        File(directory, "usr/lib/libdeck-ports.so").isFile &&
        File(directory, "usr/lib/libsteam-wine-memory.so").isFile &&
        File(directory, "usr/bin/steam-socket-peer").canExecute()

    fun install(progress: (String) -> Unit) {
        if (installed) return
        val staging = File(context.filesDir, "session-components-staging")
        try {
            require(context.filesDir.usableSpace >= 10_000_000L) { "Free at least 10 MB for Steam session components, then retry." }
            RuntimeArchive.delete(staging)
            require(staging.mkdirs()) { "Cannot create session components staging directory." }
            progress("Installing Steam session components…")
            context.assets.open("session-components.tar.xz").use { input ->
                XZInputStream(input, 64 * 1024).use { RuntimeArchive.extract(it, staging, ::checkInstallationCancelled) }
            }
            require(complete(staging)) { "An Android session adapter is missing." }
            File(staging, ".androidsteam-components").writeText(VERSION)
            checkInstallationCancelled()
            RuntimeArchive.delete(root)
            require(staging.renameTo(root)) { "Cannot publish session components." }
        } finally { RuntimeArchive.delete(staging) }
    }

    companion object { const val VERSION = "arch-android-adapters-1" }
}
