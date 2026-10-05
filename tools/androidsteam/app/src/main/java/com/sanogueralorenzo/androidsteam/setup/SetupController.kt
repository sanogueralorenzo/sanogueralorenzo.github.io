package com.sanogueralorenzo.androidsteam.setup

import android.content.Context
import com.sanogueralorenzo.androidsteam.runtime.LinuxRuntime
import com.sanogueralorenzo.androidsteam.SteamApplication
import com.sanogueralorenzo.androidsteam.session.SessionController
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.CancellationException
import java.util.concurrent.TimeUnit

internal class SetupController(private val context: Context, private val installer: SetupInstaller) {
    sealed interface State {
        data object Missing : State
        data class Working(val message: String) : State
        data class Ready(val output: String = "") : State
        data class Failed(val message: String) : State
    }

    private val linux = LinuxRuntime(context, installer.runtime.root)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val listeners = mutableSetOf<(State) -> Unit>()
    private var job: Future<*>? = null
    private var generation = 0
    @Volatile private var process: Process? = null
    @Volatile var state: State = if (installer.installed) State.Ready() else State.Missing
        private set

    fun observe(listener: (State) -> Unit) { listeners += listener; listener(state) }
    fun removeObserver(listener: (State) -> Unit) { listeners -= listener }

    fun install() = launch("Preparing Android Steam…") { token ->
        val session = (context.applicationContext as SteamApplication).session
        check(session.state == SessionController.State.Idle || session.state is SessionController.State.Failed) { "Stop Steam before downloading setup components." }
        installer.install { message -> main.post { if (generation == token) publish(State.Working(message)) } }
        State.Ready()
    }

    fun check() = launch("Starting Linux…") { _ ->
        check(installer.installed) { "Complete Download first." }
        val running = linux.startCheck()
        process = running
        try {
            // Bounded output: this command has a fixed, small response. A session will stream to a log.
            check(running.waitFor(10, TimeUnit.SECONDS)) { "Linux did not finish its startup check." }
            val output = running.inputStream.bufferedReader().use { it.readText() }
            check(running.exitValue() == 0) { "Linux startup failed (${running.exitValue()}).\n$output" }
            check(output.contains("Linux runtime ready") && output.contains("aarch64")) { "Linux returned an unexpected response.\n$output" }
            State.Ready(output.trim())
        } finally {
            running.destroy()
            try {
                if (!running.waitFor(2, TimeUnit.SECONDS)) running.destroyForcibly()
            } catch (_: InterruptedException) {
                running.destroyForcibly()
                Thread.currentThread().interrupt()
            }
            process = null
        }
    }

    private fun launch(message: String, action: (Int) -> State) {
        if (state is State.Working) return
        val token = ++generation
        publish(State.Working(message))
        job = worker.submit {
            val result = try { action(token) } catch (e: Exception) {
                State.Failed(if (e is CancellationException || e is InterruptedException) "Operation cancelled. You can retry." else e.message ?: "Setup failed. Retry Download.")
            }
            main.post { if (generation == token) publish(result) }
        }
    }

    fun stop() {
        if (state !is State.Working) return
        generation++
        process?.destroy()
        job?.cancel(true)
        publish(State.Failed("Operation cancelled. You can retry."))
    }

    private fun publish(value: State) { state = value; listeners.toList().forEach { it(value) } }
}
