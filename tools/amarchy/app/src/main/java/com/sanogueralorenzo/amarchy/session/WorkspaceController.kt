package com.sanogueralorenzo.amarchy.session

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.sanogueralorenzo.amarchy.runtime.EnvironmentInstaller
import java.util.concurrent.CancellationException

internal enum class Phase { WELCOME, PREPARING, STOPPING, FAILED }
internal data class WorkspaceState(val phase: Phase, val detail: String = "", val progress: Float = 0f)

/** One owner serializes environment preparation and cancellation. */
internal class WorkspaceController(private val context: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val listeners = mutableSetOf<(WorkspaceState) -> Unit>()
    private var worker: Thread? = null
    var state = WorkspaceState(Phase.WELCOME)
        private set

    fun observe(listener: (WorkspaceState) -> Unit) { checkMain(); listeners += listener; listener(state) }
    fun remove(listener: (WorkspaceState) -> Unit) { checkMain(); listeners -= listener }

    fun open() {
        checkMain()
        if (worker != null) return
        publish(WorkspaceState(Phase.PREPARING, "Preparing your workspace"))
        worker = Thread({
            var result = WorkspaceState(Phase.WELCOME)
            try {
                EnvironmentInstaller(context).prepare { detail, progress -> main.post {
                    if (state.phase == Phase.PREPARING) publish(WorkspaceState(Phase.PREPARING, detail, progress))
                } }
                error("Desktop startup is still in development. Your environment is prepared and will be reused.")
            } catch (_: CancellationException) {
                result = WorkspaceState(Phase.WELCOME)
            } catch (_: InterruptedException) {
                result = WorkspaceState(Phase.WELCOME)
            } catch (failure: Exception) {
                result = WorkspaceState(Phase.FAILED, failure.message ?: "Could not prepare your workspace. Try again.")
            } finally {
                main.post { worker = null; publish(result) }
            }
        }, "amarchy-workspace").apply { start() }
    }

    fun stop() { checkMain(); if (worker != null) { publish(WorkspaceState(Phase.STOPPING, "Closing your workspace")); worker?.interrupt() } }
    private fun publish(value: WorkspaceState) { state = value; listeners.toList().forEach { it(value) } }
    private fun checkMain() { check(Looper.myLooper() == Looper.getMainLooper()) }
}
