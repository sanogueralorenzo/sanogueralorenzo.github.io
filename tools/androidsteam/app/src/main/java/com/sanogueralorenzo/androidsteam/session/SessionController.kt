package com.sanogueralorenzo.androidsteam.session

import android.content.Context
import com.sanogueralorenzo.androidsteam.SteamApplication
import com.sanogueralorenzo.androidsteam.login.SteamClientBridge
import com.sanogueralorenzo.androidsteam.games.GameProfiles
import android.os.Handler
import android.os.Looper
import android.view.Surface
import com.sanogueralorenzo.androidsteam.display.NativeDisplay
import com.sanogueralorenzo.androidsteam.audio.SessionAudio
import com.sanogueralorenzo.androidsteam.runtime.RuntimeArchive
import com.sanogueralorenzo.androidsteam.runtime.checkInstallationCancelled
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.atomic.AtomicLong

/** One owner for preparation, the Steam process tree, and its native display. */
internal class SessionController(private val context: Context) {
    sealed interface State {
        data object Idle : State
        data class Working(val message: String) : State
        data object Running : State
        data object Stopping : State
        data class Failed(val message: String) : State
    }

    val pad = com.sanogueralorenzo.androidsteam.input.PadBridge()
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val listeners = mutableSetOf<(State) -> Unit>()
    private val gameListeners = mutableSetOf<(Int?) -> Unit>()
    private var generation = 0
    private data class Action(val appId: Int, val install: Boolean, val deadline: Long, val nextAttempt: Long = 0)
    private val action = AtomicReference<Action?>()
    @Volatile private var appliedRevision = -1L
    @Volatile private var hasPlayedGame = false
    // Repeated game launches can crash the ARM client, including the same game.
    // Replace the idle client through the existing path before another launch.
    val needsRestart get() = (state == State.Running || state is State.Working) &&
        (appliedRevision != GameProfiles(context).revision || action.get()?.let {
            !it.install && hasPlayedGame
        } == true)
    val actionPending get() = action.get() != null
    var actionMessage: String? = null
        private set
    private var job: Future<*>? = null
    @Volatile private var process: Process? = null
    @Volatile private var audio: SessionAudio? = null
    @Volatile var clientBridge: SteamClientBridge? = null
        private set
    @Volatile private var visible = true
    private var attachedSurface: Surface? = null
    @Volatile var state: State = State.Idle
        private set
    var gameAppId: Int? = null
        private set

    fun observe(listener: (State) -> Unit) { listeners += listener; listener(state) }
    fun removeObserver(listener: (State) -> Unit) { listeners -= listener }
    fun observeGame(listener: (Int?) -> Unit) { gameListeners += listener; listener(gameAppId) }
    fun removeGameObserver(listener: (Int?) -> Unit) { gameListeners -= listener }

    fun start(surface: Surface, width: Int, height: Int, refresh: Int) {
        if (state is State.Working || state == State.Running || state == State.Stopping) return
        begin(surface, width, height, refresh)
    }

    /** Reap the old client before projecting edited settings and starting its replacement. */
    fun restart(surface: Surface, width: Int, height: Int, refresh: Int) {
        check(state == State.Running && gameAppId == null) { "Close the running game before restarting Steam." }
        val token = ++generation
        attachedSurface = surface
        publish(State.Stopping)
        if (process == null) job?.cancel(true)
        worker.execute { main.post {
            if (generation == token) {
                if (attachedSurface === surface && surface.isValid) begin(surface, width, height, refresh)
                else publish(State.Idle)
            }
        } }
    }

    fun requestGame(appId: Int, install: Boolean) {
        require(appId > 0)
        check(gameAppId == null || gameAppId == appId) { "Another game is running. Close it before starting this game." }
        if (gameAppId == appId) return
        action.set(Action(appId, install, System.nanoTime() + TimeUnit.MINUTES.toNanos(5)))
        actionMessage = "Waiting for Steam sign-in. Complete any prompts shown below."
        publish(state)
    }

    private fun begin(surface: Surface, width: Int, height: Int, refresh: Int) {
        val token = ++generation
        hasPlayedGame = false
        visible = true
        attachedSurface = surface
        publishGame(null)
        publish(State.Working("Preparing Steam…"))
        job = worker.submit {
            val directory = File(context.cacheDir, "session")
            var running: Process? = null
            var reader: Thread? = null
            var result: State = State.Idle
            var phase = "preparing"
            var steamExit: Int? = null
            var displayExit: Int? = null
            val readFailure = AtomicReference<IOException?>()
            val startupProgress = AtomicLong(System.nanoTime())
            try {
                val progress: (String) -> Unit = { message -> update(token, State.Working(message)) }
                check(File("/dev/kgsl-3d0").exists()) { "This build requires supported Adreno graphics." }
                val preparation = (context.applicationContext as SteamApplication).preparation
                preparation.install(progress)
                val graphics = preparation.graphics
                phase = "applying-settings"
                progress("Applying game settings…")
                val profiles = GameProfiles(context)
                val revision = profiles.revision
                profiles.apply()
                appliedRevision = revision
                checkInstallationCancelled()
                RuntimeArchive.delete(directory)
                check(directory.mkdirs()) { "Cannot prepare the Steam session." }
                pad.start(directory)
                val session = SessionRuntime(context, directory)
                val games = SteamGameLog(File(context.filesDir, "home/.local/share/Steam/logs/gameprocess_log.txt"))
                val command = session.steamCommand()
                clientBridge = SteamClientBridge(directory)
                // Retain ownership before startup so partial failures also release audio.
                val playback = SessionAudio(context, directory)
                audio = playback
                playback.start()
                playback.setVisible(visible)
                phase = "starting-client"
                update(token, State.Working("Starting Steam…"))
                NativeDisplay.startVulkan(session.socket.path, surface, refresh,
                    File(graphics.root, "android").path, context.applicationInfo.nativeLibraryDir)
                checkInstallationCancelled()
                running = session.start(command, width, height)
                process = running
                val output = running.inputStream
                File(context.cacheDir, "steam-session.log").delete()
                reader = Thread({
                    try {
                        // Drain Steam output without retaining arbitrary subprocess values.
                        output.bufferedReader().useLines { lines -> lines.forEach { line ->
                            if (line.startsWith("[----]")) startupProgress.set(System.nanoTime())
                            if (line.contains("Set status message: ")) {
                                startupProgress.set(System.nanoTime())
                                update(token, State.Working("Connecting to Steam…"))
                            }
                        } }
                    } catch (failure: IOException) { readFailure.set(failure) }
                }, "Steam output").apply { start() }
                var displayed = false
                var nextGameCheck = 0L
                var activeGame: Int? = null
                while (!running.waitFor(100, TimeUnit.MILLISECONDS)) {
                    checkInstallationCancelled()
                    if (state == State.Stopping) {
                        // Let Steam flush its own state; cleanup still forcibly
                        // reaps the process tree if shutdown cannot complete.
                        try { session.requestShutdown() } catch (_: Exception) { }
                        running.waitFor(10, TimeUnit.SECONDS)
                        break
                    }
                    readFailure.get()?.let { throw it }
                    audio?.failure?.let { throw it }
                    if (System.nanoTime() >= nextGameCheck) {
                        nextGameCheck = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(500)
                        val appId = games.read()
                        phase = when {
                            appId != null -> "game-running"
                            action.get() != null && games.clientReady -> "waiting-game"
                            games.clientReady -> "client-ready"
                            displayed -> "display-ready"
                            else -> "starting-client"
                        }
                        deliverAction(token, games.clientReady, appId)
                        if (activeGame != appId) {
                            activeGame = appId
                            main.post { if (generation == token) publishGame(appId) }
                        }
                    }
                    if (!displayed && NativeDisplay.snapshot()[0] > 0) {
                        displayed = true
                        update(token, State.Running)
                    }
                    check(displayed || System.nanoTime() - startupProgress.get() < TimeUnit.SECONDS.toNanos(90)) { "Steam startup stalled. Tap Library, then Play or Profile → Open Steam to retry." }
                }
                steamExit = File(directory, "steam-exit").takeIf { it.isFile }?.readText()?.trim()?.toIntOrNull()
                displayExit = if (running.isAlive) null else running.exitValue()
                check(steamExit != null) { "Steam ended without an exit status. Tap Library, then Play or Profile → Open Steam to retry." }
                check(steamExit == 0) { "Steam stopped unexpectedly (exit code $steamExit). Tap Library, then Play or Profile → Open Steam to retry." }
                check(displayExit == 0) { "Steam display stopped (exit code $displayExit). Tap Library, then Play or Profile → Open Steam to retry." }
            } catch (failure: Exception) {
                // Only controlled phases, public app IDs and numeric exit codes.
                // Never log raw Steam output, account data, paths or exception contents.
                if (generation == token && state != State.Stopping) {
                    val cause = if (audio?.failure != null) "audio" else if (steamExit != null) "steam-exit" else "startup-or-display"
                    android.util.Log.e("SteamSession", "failure cause=$cause phase=$phase appId=${action.get()?.appId ?: gameAppId ?: 0} steamExit=$steamExit displayExit=$displayExit")
                }
                val message = failure.message ?: "Steam could not start."
                result = State.Failed(if (message.contains("Tap Library")) message
                    else "$message\nTap Library, then Play or Profile → Open Steam to retry.")
            } finally {
                val interrupted = Thread.interrupted()
                try {
                    running?.destroy()
                    if (running?.waitFor(2, TimeUnit.SECONDS) == false) { running.destroyForcibly(); running.waitFor(2, TimeUnit.SECONDS) }
                    reader?.join(2_000)
                } catch (_: InterruptedException) {
                    running?.destroyForcibly()
                } finally {
                    process = null
                    try { audio?.close() } finally {
                        audio = null
                        try { clientBridge?.close() } finally {
                            clientBridge = null
                            pad.close()
                            NativeDisplay.stop()
                            RuntimeArchive.delete(directory)
                        }
                    }
                    if (interrupted) Thread.currentThread().interrupt()
                }
            }
            update(token, result)
            main.post { if (generation == token) publishGame(null) }
        }
    }

    fun stop() {
        if (state == State.Idle || state == State.Stopping || state is State.Failed) return
        val token = ++generation
        action.set(null)
        actionMessage = null
        publishGame(null)
        publish(State.Stopping)
        if (process == null) job?.cancel(true)
        worker.execute { update(token, State.Idle) }
    }

    fun attach(surface: Surface) {
        attachedSurface = surface
        visible = true
        if (state == State.Running || state is State.Working) {
            NativeDisplay.attach(surface)
            audio?.setVisible(true)
        }
    }

    fun detach(surface: Surface) {
        // A departing activity can destroy its surface after a replacement has
        // already attached. It must not detach or mute the replacement.
        if (attachedSurface !== surface) return
        attachedSurface = null
        visible = false
        if (state == State.Running || state is State.Working) {
            NativeDisplay.attach(null)
            audio?.setVisible(false)
        }
    }

    private fun update(token: Int, value: State) { main.post {
        if (generation == token && !(state == State.Running && value is State.Working)) {
            if (value == State.Idle || value is State.Failed) { action.set(null); actionMessage = null }
            publish(value)
        }
    } }

    /** Submit Steam's public URI through its already-connected local client. */
    private fun deliverAction(token: Int, ready: Boolean, activeAppId: Int?) {
        if (state == State.Stopping) return
        val requested = action.get() ?: return
        if (!requested.install && activeAppId == requested.appId) {
            if (action.compareAndSet(requested, null)) main.post {
                if (generation == token) { actionMessage = null; publish(state) }
            }
            return
        }
        val now = System.nanoTime()
        if ((!ready || needsRestart || now < requested.nextAttempt) && now <= requested.deadline) return
        // Client mode appears before Steam finishes loading the signed-in user.
        // Do not enqueue a launch into that unfinished startup state. Reuse the
        // existing read-only observer with a short total deadline so Stop stays responsive.
        if (now <= requested.deadline) {
            val signedIn = try { clientBridge?.hasCurrentUser(1_500) == true } catch (_: Exception) { false }
            if (!signedIn) {
                action.compareAndSet(requested, requested.copy(nextAttempt = System.nanoTime() + TimeUnit.SECONDS.toNanos(1)))
                return
            }
        }
        val failure = if (System.nanoTime() > requested.deadline) "Steam did not start the game within 5 minutes. Complete any Steam prompts, then tap Library → Play to retry."
        else try {
            check(clientBridge?.requestGame(requested.appId, requested.install) == true) {
                "Steam's game interface is unavailable. Complete any Steam prompts, then tap Library → Play to retry."
            }
            null
        } catch (error: Exception) { error.message ?: "Steam could not accept the game request." }
        // A submitted URI only proves forwarding, not acceptance.
        // Steam deduplicates requests for one app; retain Play until its process
        // event acknowledges it, retrying startup misses within the same deadline.
        val pending = if (failure == null && !requested.install)
            requested.copy(nextAttempt = System.nanoTime() + TimeUnit.SECONDS.toNanos(10)) else null
        if (action.compareAndSet(requested, pending)) main.post {
            if (generation == token) {
                actionMessage = if (pending != null) "Starting game… Complete any Steam prompts shown below." else failure
                publish(state)
            }
        }
    }
    private fun publish(value: State) { state = value; listeners.toList().forEach { it(value) } }
    private fun publishGame(appId: Int?) {
        if (gameAppId == appId) return
        if (appId != null) hasPlayedGame = true
        gameAppId = appId
        gameListeners.toList().forEach { it(appId) }
    }
}
