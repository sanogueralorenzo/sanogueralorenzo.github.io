package com.sanogueralorenzo.amarchy.session

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Surface
import android.util.Log
import com.sanogueralorenzo.amarchy.display.NativeDisplay
import com.sanogueralorenzo.amarchy.runtime.EnvironmentInstaller
import java.util.concurrent.CancellationException
import java.util.concurrent.Executors

internal enum class Phase { WELCOME, PREPARING, STARTING, RUNNING, STOPPING, FAILED }
internal data class WorkspaceState(val phase: Phase, val detail: String = "", val progress: Float = 0f)

/** One owner prepares, starts, monitors and reaps the desktop and its Android display. */
internal class WorkspaceController(private val context: Context) {
    private val main = Handler(Looper.getMainLooper())
    private val listeners = mutableSetOf<(WorkspaceState) -> Unit>()
    private var worker: Thread? = null
    private val surfaceGate = Object()
    private var surface: Surface? = null
    private var displayStarted = false
    @Volatile private var session: DesktopSession? = null
    private val commands = Executors.newSingleThreadExecutor { job -> Thread(job, "amarchy-desktop-command") }
    @Volatile
    var state = WorkspaceState(Phase.WELCOME)
        private set

    fun observe(listener: (WorkspaceState) -> Unit) { checkMain(); listeners += listener; listener(state) }
    fun remove(listener: (WorkspaceState) -> Unit) { checkMain(); listeners -= listener }

    fun open() {
        checkMain()
        if (worker != null || state.phase == Phase.RUNNING) return
        publish(WorkspaceState(Phase.PREPARING, "Preparing your workspace"))
        worker = Thread({
            var result = WorkspaceState(Phase.WELCOME)
            try {
                EnvironmentInstaller(context).prepare { detail, progress -> main.post {
                    if (state.phase == Phase.PREPARING) publish(WorkspaceState(Phase.PREPARING, detail, progress))
                } }
                val desktop = DesktopSession(context).also { session = it; it.prepare() }
                main.post { if (state.phase != Phase.STOPPING) publish(WorkspaceState(Phase.STARTING, "Opening your desktop")) }
                synchronized(surfaceGate) {
                    while (surface?.isValid != true) surfaceGate.wait()
                    NativeDisplay.start(desktop.socket.path, surface!!, 30_000)
                    displayStarted = true
                }
                desktop.start()
                val desktopStarted = SystemClock.elapsedRealtime()
                val deadline = SystemClock.elapsedRealtime() + 90_000
                while (desktop.alive && SystemClock.elapsedRealtime() < deadline) {
                    if (Thread.currentThread().isInterrupted) throw InterruptedException()
                    if (NativeDisplay.snapshot()[0] > 0 && desktop.terminalMapped()) break
                    Thread.sleep(250)
                }
                check(desktop.alive && desktop.terminalMapped()) { "Your desktop did not finish opening. Try again." }
                Log.i("AmarchySession", "desktopReadyMs=${SystemClock.elapsedRealtime() - desktopStarted}")
                main.post { if (state.phase != Phase.STOPPING) publish(WorkspaceState(Phase.RUNNING, "Your desktop is open")) }
                val exit = desktop.waitForExit()
                check(exit == 0) { "The desktop closed unexpectedly. Open it again to continue." }
            } catch (_: CancellationException) {
                result = WorkspaceState(Phase.WELCOME)
            } catch (_: InterruptedException) {
                result = WorkspaceState(Phase.WELCOME)
            } catch (failure: Exception) {
                result = if (state.phase == Phase.STOPPING) WorkspaceState(Phase.WELCOME) else
                    WorkspaceState(Phase.FAILED, failure.message ?: "Could not open your workspace. Try again.")
            } finally {
                Thread.interrupted()
                session?.close(); session = null
                synchronized(surfaceGate) { NativeDisplay.stop(); displayStarted = false }
                main.post { worker = null; publish(result) }
            }
        }, "amarchy-workspace").apply { start() }
    }

    fun stop() {
        checkMain()
        if (worker == null) { if (state.phase != Phase.WELCOME) publish(WorkspaceState(Phase.WELCOME)); return }
        publish(WorkspaceState(Phase.STOPPING, "Closing your workspace")); worker?.interrupt()
    }
    fun attach(value: Surface?) {
        checkMain()
        synchronized(surfaceGate) {
            surface = value
            if (displayStarted) NativeDisplay.attach(value)
            surfaceGate.notifyAll()
        }
    }
    fun launch(command: String) {
        val quoted = command.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n").replace("\r", "\\r")
        execute(listOf("/usr/bin/hyprctl", "dispatch", "hl.dsp.exec_cmd('$quoted')"))
    }
    fun type(text: String) { if (text.isNotEmpty()) execute(listOf("/usr/bin/wtype", "--", text)) }
    fun shortcut(vararg codes: Int) {
        if (state.phase != Phase.RUNNING) return
        codes.forEach { NativeDisplay.key(it, true) }
        codes.reversed().forEach { NativeDisplay.key(it, false) }
    }
    private fun execute(arguments: List<String>) {
        if (state.phase != Phase.RUNNING) return
        commands.execute {
            try { session?.command(arguments) } catch (_: Exception) {
                main.post { if (state.phase == Phase.RUNNING) publish(state.copy(detail = "That action could not finish. Try it again.")) }
            }
        }
    }
    private fun publish(value: WorkspaceState) { state = value; listeners.toList().forEach { it(value) } }
    private fun checkMain() { check(Looper.myLooper() == Looper.getMainLooper()) }
}
