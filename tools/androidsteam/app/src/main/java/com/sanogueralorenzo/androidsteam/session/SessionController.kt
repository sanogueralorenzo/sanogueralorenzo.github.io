package com.sanogueralorenzo.androidsteam.session

import android.content.Context
import com.sanogueralorenzo.androidsteam.SteamApplication
import com.sanogueralorenzo.androidsteam.games.GameProfiles
import android.os.Handler
import android.os.Looper
import android.view.Surface
import android.system.Os
import android.system.OsConstants
import android.system.ErrnoException
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

    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val listeners = mutableSetOf<(State) -> Unit>()
    private val gameListeners = mutableSetOf<(Int?) -> Unit>()
    private var generation = 0
    private data class Action(val appId: Int, val install: Boolean, val deadline: Long)
    private val action = AtomicReference<Action?>()
    @Volatile private var appliedRevision = -1L
    val needsRestart get() = (state == State.Running || state is State.Working) && appliedRevision != GameProfiles(context).revision
    var actionMessage: String? = null
        private set
    private var job: Future<*>? = null
    @Volatile private var process: Process? = null
    @Volatile private var audio: SessionAudio? = null
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
        process?.destroy()
        job?.cancel(true)
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
        actionMessage = "Waiting for Steam. Complete any sign-in or installation prompts."
        publish(state)
    }

    private fun begin(surface: Surface, width: Int, height: Int, refresh: Int) {
        val token = ++generation
        visible = true
        attachedSurface = surface
        publishGame(null)
        publish(State.Working("Preparing Steam…"))
        job = worker.submit {
            val directory = File(context.cacheDir, "session")
            var running: Process? = null
            var reader: Thread? = null
            var result: State = State.Idle
            val readFailure = AtomicReference<IOException?>()
            val startupProgress = AtomicLong(System.nanoTime())
            try {
                val progress: (String) -> Unit = { message -> update(token, State.Working(message)) }
                check(File("/dev/kgsl-3d0").exists()) { "This build requires supported Adreno graphics." }
                val preparation = (context.applicationContext as SteamApplication).preparation
                preparation.install(progress)
                val graphics = preparation.graphics
                progress("Applying game settings…")
                val profiles = GameProfiles(context)
                val revision = profiles.revision
                profiles.apply()
                appliedRevision = revision
                checkInstallationCancelled()
                RuntimeArchive.delete(directory)
                check(directory.mkdirs()) { "Cannot prepare the Steam session." }
                val session = SessionRuntime(context, directory)
                val games = SteamGameLog(File(context.filesDir, "home/.local/share/Steam/logs/gameprocess_log.txt"))
                val command = session.steamCommand()
                // Retain ownership before startup so partial failures also release audio.
                val playback = SessionAudio(context, directory)
                audio = playback
                playback.start()
                playback.setVisible(visible)
                update(token, State.Working("Starting Steam…"))
                NativeDisplay.startVulkan(session.socket.path, surface, refresh,
                    File(graphics.root, "android").path, context.applicationInfo.nativeLibraryDir)
                checkInstallationCancelled()
                running = session.start(command, width, height)
                process = running
                val output = running.inputStream
                val log = File(context.cacheDir, "steam-session.log")
                reader = Thread({
                    try {
                        java.io.RandomAccessFile(log, "rw").use { file ->
                            file.setLength(0)
                            output.bufferedReader().useLines { lines -> lines.forEach { line ->
                                    val bytes = (line.take(8192) + "\n").toByteArray()
                                    if (file.filePointer + bytes.size > 1_048_576) { file.setLength(0); file.seek(0) }
                                    file.write(bytes)
                                    if (line.startsWith("[----]")) startupProgress.set(System.nanoTime())
                                    val marker = "Set status message: "
                                    val position = line.indexOf(marker)
                                    if (position >= 0) {
                                        startupProgress.set(System.nanoTime())
                                        update(token, State.Working(line.substring(position + marker.length).trim()))
                                    }
                                }
                            }
                        }
                    } catch (failure: IOException) { readFailure.set(failure) }
                }, "Steam output").apply { start() }
                var displayed = false
                var nextGameCheck = 0L
                var activeGame: Int? = null
                while (!running.waitFor(100, TimeUnit.MILLISECONDS)) {
                    checkInstallationCancelled()
                    readFailure.get()?.let { throw it }
                    audio?.failure?.let { throw it }
                    if (System.nanoTime() >= nextGameCheck) {
                        nextGameCheck = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(500)
                        val appId = games.read()
                        deliverAction(token, games.clientReady)
                        if (activeGame != appId) {
                            activeGame = appId
                            main.post { if (generation == token) publishGame(appId) }
                        }
                    }
                    if (!displayed && NativeDisplay.snapshot()[0] > 0) {
                        displayed = true
                        update(token, State.Running)
                    }
                    check(displayed || System.nanoTime() - startupProgress.get() < TimeUnit.SECONDS.toNanos(90)) { "Steam startup stalled. Stop and retry; startup details are in the app's private log." }
                }
                val status = File(directory, "steam-exit").takeIf { it.isFile }?.readText()?.trim()?.toIntOrNull()
                check(status != null) { "Steam ended without reporting its exit status. Restart Steam." }
                check(status == 0) { "Steam stopped unexpectedly (exit code $status). Restart Steam." }
                check(running.exitValue() == 0) { "Steam display stopped with exit code ${running.exitValue()}. Restart Steam." }
            } catch (failure: Exception) {
                result = State.Failed(failure.message ?: "Steam could not start. Retry the session.")
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
                        NativeDisplay.stop()
                        RuntimeArchive.delete(directory)
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
        process?.destroy()
        job?.cancel(true)
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

    /** Steam's existing FIFO accepts fixed URIs; opening it never starts a second client. */
    private fun deliverAction(token: Int, ready: Boolean) {
        if (state == State.Stopping) return
        val requested = action.get() ?: return
        if ((!ready || appliedRevision != GameProfiles(context).revision) && System.nanoTime() <= requested.deadline) return
        val failure = if (System.nanoTime() > requested.deadline) "Steam did not accept the request. Complete its prompts, then try Play again."
        else try {
            val file = Os.open(File(context.filesDir, "home/.steam/steam.pipe").path,
                OsConstants.O_WRONLY or OsConstants.O_NONBLOCK or OsConstants.O_CLOEXEC, 0)
            try {
                check(OsConstants.S_ISFIFO(Os.fstat(file).st_mode)) { "Steam's command channel is unavailable. Restart Steam." }
                val uri = "steam://${if (requested.install) "install" else "rungameid"}/${requested.appId}\n".toByteArray(Charsets.US_ASCII)
                check(Os.write(file, uri, 0, uri.size) == uri.size) { "Steam did not accept the game request. Try again." }
            } finally { Os.close(file) }
            null
        } catch (error: ErrnoException) {
            if (error.errno in listOf(OsConstants.ENOENT, OsConstants.ENXIO, OsConstants.EAGAIN)) return
            "Steam's command channel failed. Restart Steam, then try again."
        } catch (error: Exception) { error.message ?: "Steam could not accept the game request." }
        if (action.compareAndSet(requested, null)) main.post {
            if (generation == token) { actionMessage = failure; publish(state) }
        }
    }
    private fun publish(value: State) { state = value; listeners.toList().forEach { it(value) } }
    private fun publishGame(appId: Int?) {
        if (gameAppId == appId) return
        gameAppId = appId
        gameListeners.toList().forEach { it(appId) }
    }
}
