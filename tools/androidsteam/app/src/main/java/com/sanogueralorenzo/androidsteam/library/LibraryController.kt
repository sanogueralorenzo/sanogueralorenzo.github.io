package com.sanogueralorenzo.androidsteam.library

import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors

/** One background reader shared by library and details; no Steam session ownership. */
internal class LibraryController(private val context: Context) {
    data class State(val snapshot: LibrarySnapshot? = null, val loading: Boolean = false, val error: String? = null)
    private val library = SteamLibrary(context)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val listeners = mutableSetOf<(State) -> Unit>()
    private var busy = false
    var state = State()
        private set
    private val poll = Runnable { load() }

    fun observe(listener: (State) -> Unit) {
        listeners += listener
        listener(state)
        if (listeners.size == 1) load(refresh = state.snapshot == null &&
            (context.applicationContext as com.sanogueralorenzo.androidsteam.SteamApplication).session.state == com.sanogueralorenzo.androidsteam.session.SessionController.State.Running)
    }
    fun removeObserver(listener: (State) -> Unit) {
        listeners -= listener
        if (listeners.isEmpty()) main.removeCallbacks(poll)
    }
    fun load(refresh: Boolean = false) {
        if (busy) return
        busy = true
        main.removeCallbacks(poll)
        if (refresh || state.snapshot == null) publish(state.copy(loading = true))
        worker.execute {
            val result = try { State(if (refresh) library.refresh() else library.read()) }
            catch (failure: Exception) { State(snapshot = runCatching { library.read() }.getOrNull(),
                error = failure.message ?: "The library could not load. Open Steam, then refresh.") }
            main.post {
                busy = false
                // Reject stale ownership when account selection changes or data becomes invalid.
                publish(result)
                if (listeners.isNotEmpty() && result.snapshot != null) main.postDelayed(poll, 5_000)
            }
        }
    }
    private fun publish(value: State) { state = value; listeners.toList().forEach { it(value) } }
}
