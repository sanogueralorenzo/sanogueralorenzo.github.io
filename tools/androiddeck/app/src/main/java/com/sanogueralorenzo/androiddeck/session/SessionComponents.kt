package com.sanogueralorenzo.androiddeck.session

import android.content.Context
import com.sanogueralorenzo.androiddeck.runtime.RuntimeArchive
import com.sanogueralorenzo.androiddeck.runtime.checkInstallationCancelled
import java.io.File
import org.tukaani.xz.XZInputStream

internal class SessionComponents(private val context: Context) {
    val root = File(context.filesDir, "session-components")
    val installed get() = File(root, ".androiddeck-components").takeIf { it.isFile }?.readText() == VERSION &&
        File(root, "usr/games/gamescope").canExecute() && File(root, "usr/bin/Xwayland").canExecute()

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
            require(File(staging, "usr/games/gamescope").canExecute() && File(staging, "usr/bin/Xwayland").canExecute()) { "Session components are missing Gamescope or XWayland." }
            File(staging, ".androiddeck-components").writeText(VERSION)
            checkInstallationCancelled()
            RuntimeArchive.delete(root)
            require(staging.renameTo(root)) { "Cannot publish session components." }
        } finally { RuntimeArchive.delete(staging) }
    }

    companion object { const val VERSION = "resolute-gamescope-3.16.20-components-3" }
}
