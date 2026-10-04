package com.sanogueralorenzo.androiddeck.runtime

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.CancellationException
import java.util.concurrent.TimeUnit

internal class RuntimeController(context: Context) {
    sealed interface State {
        data object Missing : State
        data class Working(val message: String) : State
        data class Ready(val output: String = "") : State
        data class Failed(val message: String, val installed: Boolean) : State
    }

    private val installer = RuntimeInstaller(context.filesDir, context.cacheDir)
    private val linux = LinuxRuntime(context, installer.root)
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

    fun install() = launch("Preparing runtime…") { token ->
        installer.install { message -> main.post { if (generation == token) publish(State.Working(message)) } }
        State.Ready()
    }

    fun check() = launch("Starting Linux…") { _ ->
        check(installer.installed) { "Install the Linux runtime first." }
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
                if (e !is CancellationException && e !is InterruptedException) Log.e("AndroidDeck", "Runtime operation failed", e)
                State.Failed(if (e is CancellationException) "Operation cancelled. You can retry." else e.message ?: "Runtime operation failed. Retry.", installer.installed)
            }
            main.post { if (generation == token) publish(result) }
        }
    }

    fun stop() {
        generation++
        process?.destroy()
        job?.cancel(true)
        publish(State.Failed("Operation cancelled. You can retry.", installer.installed))
    }

    private fun publish(value: State) { state = value; listeners.toList().forEach { it(value) } }
}
