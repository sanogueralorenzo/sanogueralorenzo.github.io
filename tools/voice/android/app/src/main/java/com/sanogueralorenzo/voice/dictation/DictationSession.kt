package com.sanogueralorenzo.voice.dictation

import android.os.Handler
import android.os.Looper
import com.sanogueralorenzo.voice.dictation.DictationEditCommand
import com.sanogueralorenzo.voice.dictation.DictationLanguage
import com.sanogueralorenzo.voice.dictation.DictationTextBuffer
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

/**
 * Owns the complete lifecycle of one microphone dictation at a time.
 *
 * Editor-specific behavior remains in the Keyboard and Overlay products. This class only owns
 * transcription, final-line settling, command recognition, and guaranteed microphone cleanup.
 */
internal class DictationSession(
    private val transcriber: DictationTranscriber,
    private val listener: Listener,
    private val worker: Worker = ExecutorWorker(),
    private val scheduler: Scheduler = HandlerScheduler()
) {
    enum class State {
        IDLE,
        RECORDING,
        STOPPING,
        CLOSED
    }

    data class Result(
        val text: String,
        val hasTranscript: Boolean,
        val command: DictationEditCommand?
    )

    interface Listener {
        fun onStateChanged(state: State) = Unit
        fun onTextChanged(text: String) = Unit
        fun onAudioLevel(level: Float) = Unit
        fun onCompleted(result: Result) = Unit
        fun onCancelled() = Unit
        fun onError(error: Throwable?) = Unit
    }

    private data class ActiveSession(
        val id: Int,
        val buffer: DictationTextBuffer,
        var acceptsCallbacks: Boolean = true
    )

    var state: State = State.IDLE
        private set

    val isActive: Boolean
        get() = state == State.RECORDING || state == State.STOPPING

    private var nextSessionId = 0
    private var activeSession: ActiveSession? = null

    fun isReady(language: DictationLanguage): Boolean = transcriber.isReady(language)

    fun warmup(language: DictationLanguage) {
        if (state == State.CLOSED) return
        worker.execute { transcriber.warmup(language) }
    }

    fun start(language: DictationLanguage, originalText: String): Boolean {
        if (state != State.IDLE) return false
        val session = ActiveSession(
            id = ++nextSessionId,
            buffer = DictationTextBuffer(originalText)
        )
        activeSession = session
        moveTo(State.RECORDING)
        worker.execute {
            val started = transcriber.start(
                language = language,
                callbacks = DictationTranscriber.Callbacks(
                    onText = { text -> scheduler.post { onText(session.id, text) } },
                    onLine = { id, text -> scheduler.post { onLine(session.id, id, text) } },
                    onError = { error -> scheduler.post { fail(session.id, error) } },
                    onAudioLevel = { level ->
                        scheduler.post {
                            if (activeSession?.id == session.id && state == State.RECORDING) {
                                if (session.acceptsCallbacks) listener.onAudioLevel(level)
                            }
                        }
                    }
                )
            )
            if (!started) {
                scheduler.post { fail(session.id, null) }
            }
        }
        return true
    }

    fun stop(): Boolean {
        val session = activeSession ?: return false
        if (state != State.RECORDING) return false
        moveTo(State.STOPPING)
        worker.execute {
            transcriber.stop()
            scheduler.post {
                if (activeSession?.id == session.id && state == State.STOPPING) {
                    scheduleFinish(session.id, FINAL_TRANSCRIPT_TIMEOUT_MS)
                }
            }
        }
        return true
    }

    fun cancel(): Boolean {
        val session = activeSession ?: return false
        if (!isActive) return false
        scheduler.cancelDelayed()
        session.acceptsCallbacks = false
        transcriber.detachCallbacks()
        moveTo(State.STOPPING)
        closeTranscriber(session.id) {
            activeSession = null
            moveTo(State.IDLE)
            listener.onCancelled()
        }
        return true
    }

    fun destroy() {
        if (state == State.CLOSED) return
        scheduler.cancelDelayed()
        activeSession = null
        state = State.CLOSED
        listener.onStateChanged(State.CLOSED)
        transcriber.detachCallbacks()
        worker.shutdown()
        transcriber.close()
    }

    private fun onText(sessionId: Int, text: String) {
        val session = activeSession?.takeIf { it.id == sessionId && it.acceptsCallbacks } ?: return
        listener.onTextChanged(session.buffer.updatePartial(text))
        if (state == State.STOPPING) {
            scheduleFinish(sessionId, FINAL_TRANSCRIPT_TIMEOUT_MS)
        }
    }

    private fun onLine(sessionId: Int, lineId: Long, text: String) {
        val session = activeSession?.takeIf { it.id == sessionId && it.acceptsCallbacks } ?: return
        listener.onTextChanged(session.buffer.completeLine(lineId, text))
        if (state == State.STOPPING) {
            scheduleFinish(sessionId, FINAL_LINE_SETTLE_MS)
        }
    }

    private fun scheduleFinish(sessionId: Int, delayMs: Long) {
        if (activeSession?.id != sessionId || state != State.STOPPING) return
        scheduler.replaceDelayed(delayMs) { finish(sessionId) }
    }

    private fun finish(sessionId: Int) {
        val session = activeSession?.takeIf { it.id == sessionId } ?: return
        if (state != State.STOPPING) return
        scheduler.cancelDelayed()
        session.acceptsCallbacks = false
        transcriber.detachCallbacks()
        val result = Result(
            text = session.buffer.currentText(),
            hasTranscript = session.buffer.hasTranscript,
            command = session.buffer.command()
        )
        closeTranscriber(sessionId) {
            activeSession = null
            moveTo(State.IDLE)
            listener.onCompleted(result)
        }
    }

    private fun fail(sessionId: Int, error: Throwable?) {
        val session = activeSession?.takeIf { it.id == sessionId && it.acceptsCallbacks } ?: return
        scheduler.cancelDelayed()
        session.acceptsCallbacks = false
        transcriber.detachCallbacks()
        moveTo(State.STOPPING)
        closeTranscriber(sessionId) {
            activeSession = null
            moveTo(State.IDLE)
            listener.onError(error)
        }
    }

    private fun closeTranscriber(sessionId: Int, afterClose: () -> Unit) {
        worker.execute {
            transcriber.close()
            scheduler.post {
                if (state != State.CLOSED && activeSession?.id == sessionId) {
                    afterClose()
                }
            }
        }
    }

    private fun moveTo(newState: State) {
        if (state == newState) return
        state = newState
        listener.onStateChanged(newState)
    }

    internal interface Worker {
        fun execute(block: () -> Unit)
        fun shutdown()
    }

    internal interface Scheduler {
        fun post(block: () -> Unit)
        fun replaceDelayed(delayMs: Long, block: () -> Unit)
        fun cancelDelayed()
    }

    private class ExecutorWorker : Worker {
        private val executor: ExecutorService = Executors.newSingleThreadExecutor()

        override fun execute(block: () -> Unit) {
            try {
                executor.execute(block)
            } catch (_: RejectedExecutionException) {
                // Ignore late work while the Android service is shutting down.
            }
        }

        override fun shutdown() {
            executor.shutdownNow()
        }
    }

    private class HandlerScheduler : Scheduler {
        private val handler = Handler(Looper.getMainLooper())
        private var delayed: Runnable? = null

        override fun post(block: () -> Unit) {
            if (Looper.myLooper() == handler.looper) {
                block()
            } else {
                handler.post(block)
            }
        }

        override fun replaceDelayed(delayMs: Long, block: () -> Unit) {
            cancelDelayed()
            delayed = Runnable {
                delayed = null
                block()
            }.also { handler.postDelayed(it, delayMs) }
        }

        override fun cancelDelayed() {
            delayed?.let(handler::removeCallbacks)
            delayed = null
        }
    }

    private companion object {
        const val FINAL_TRANSCRIPT_TIMEOUT_MS = 800L
        const val FINAL_LINE_SETTLE_MS = 50L
    }
}
