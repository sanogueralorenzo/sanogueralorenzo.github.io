package com.sanogueralorenzo.androidsteam.setup

import android.content.Context
import com.sanogueralorenzo.androidsteam.display.GraphicsInstaller
import com.sanogueralorenzo.androidsteam.runtime.RuntimeInstaller
import com.sanogueralorenzo.androidsteam.runtime.checkInstallationCancelled
import com.sanogueralorenzo.androidsteam.session.SessionComponents
import com.sanogueralorenzo.androidsteam.session.SteamInstaller
import java.util.concurrent.locks.ReentrantLock

/** Shared by Download and session startup; only one preparation can mutate components. */
internal class SetupInstaller(context: Context) {
    val runtime = RuntimeInstaller(context)
    val graphics = GraphicsInstaller(context)
    private val components = SessionComponents(context)
    private val steam = SteamInstaller(context)
    private val lock = ReentrantLock()
    val installed get() = runtime.installed && graphics.installed && components.installed && steam.installed

    fun install(progress: (String) -> Unit) {
        lock.lockInterruptibly()
        try {
            checkInstallationCancelled()
            progress("Preparing shared components…")
            runtime.install(progress)
            graphics.install(progress)
            components.install(progress)
            steam.install(progress)
            check(installed) { "Setup is incomplete. Retry Download." }
        } finally { lock.unlock() }
    }
}
