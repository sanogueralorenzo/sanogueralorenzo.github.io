package com.sanogueralorenzo.voice.dictation

import com.sanogueralorenzo.voice.dictation.DictationEditCommand
import com.sanogueralorenzo.voice.dictation.DictationLanguage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DictationSessionTest {
    @Test
    fun stopWaitsForFinalLineAndClosesBeforeCompleting() {
        val fixture = Fixture()

        assertTrue(fixture.session.start(DictationLanguage.ENGLISH, originalText = ""))
        fixture.transcriber.callbacks?.onText?.invoke("hello their")
        assertEquals("hello their", fixture.listener.text)

        assertTrue(fixture.session.stop())
        assertEquals(800L, fixture.scheduler.delayMs)
        fixture.transcriber.callbacks?.onLine?.invoke(1L, "Hello there.")
        assertEquals(50L, fixture.scheduler.delayMs)
        assertNull(fixture.listener.completed)

        fixture.scheduler.runDelayed()

        assertEquals(listOf("start", "stop", "detach", "close"), fixture.transcriber.calls)
        assertEquals("Hello there.", fixture.listener.completed?.text)
        assertEquals(DictationSession.State.IDLE, fixture.session.state)
    }

    @Test
    fun commandIsOnlyReturnedAfterTheRecordingCompletes() {
        val fixture = Fixture()

        fixture.session.start(DictationLanguage.ENGLISH, originalText = "Buy milk")
        fixture.transcriber.callbacks?.onText?.invoke("CLEAR.,")

        assertEquals("Buy milk", fixture.listener.text)
        assertNull(fixture.listener.completed)

        fixture.session.stop()
        fixture.scheduler.runDelayed()

        assertEquals(DictationEditCommand.Clear, fixture.listener.completed?.command)
        assertEquals("", fixture.listener.completed?.text)
    }

    @Test
    fun cancelClosesWithoutCompletingAndIgnoresLateCallbacks() {
        val fixture = Fixture()
        fixture.session.start(DictationLanguage.SPANISH, originalText = "Original")
        val staleCallbacks = fixture.transcriber.callbacks

        assertTrue(fixture.session.cancel())
        staleCallbacks?.onText?.invoke("late text")

        assertTrue(fixture.listener.cancelled)
        assertNull(fixture.listener.completed)
        assertNull(fixture.listener.text)
        assertEquals(DictationSession.State.IDLE, fixture.session.state)
        assertEquals(listOf("start", "detach", "close"), fixture.transcriber.calls)
    }

    @Test
    fun startFailureClosesBeforeReportingTheError() {
        val fixture = Fixture(startResult = false)

        assertTrue(fixture.session.start(DictationLanguage.ENGLISH, originalText = ""))

        assertTrue(fixture.listener.failed)
        assertEquals(DictationSession.State.IDLE, fixture.session.state)
        assertEquals(listOf("start", "detach", "close"), fixture.transcriber.calls)
    }

    @Test
    fun aSecondSessionCannotStartWhileRecordingOrStopping() {
        val fixture = Fixture()

        assertTrue(fixture.session.start(DictationLanguage.ENGLISH, originalText = ""))
        assertFalse(fixture.session.start(DictationLanguage.SPANISH, originalText = ""))
        fixture.session.stop()
        assertFalse(fixture.session.start(DictationLanguage.SPANISH, originalText = ""))
    }

    private class Fixture(startResult: Boolean = true) {
        val transcriber = FakeTranscriber(startResult)
        val listener = RecordingListener()
        val scheduler = ManualScheduler()
        val session = DictationSession(
            transcriber = transcriber,
            listener = listener,
            worker = ImmediateWorker,
            scheduler = scheduler
        )
    }

    private class FakeTranscriber(
        private val startResult: Boolean
    ) : DictationTranscriber {
        val calls = mutableListOf<String>()
        var callbacks: DictationTranscriber.Callbacks? = null

        override fun warmup(language: DictationLanguage): Boolean = true

        override fun isReady(language: DictationLanguage): Boolean = true

        override fun start(
            language: DictationLanguage,
            callbacks: DictationTranscriber.Callbacks
        ): Boolean {
            calls += "start"
            this.callbacks = callbacks
            return startResult
        }

        override fun stop() {
            calls += "stop"
        }

        override fun detachCallbacks() {
            calls += "detach"
            callbacks = null
        }

        override fun close() {
            calls += "close"
            callbacks = null
        }
    }

    private class RecordingListener : DictationSession.Listener {
        var text: String? = null
        var completed: DictationSession.Result? = null
        var cancelled = false
        var failed = false

        override fun onTextChanged(text: String) {
            this.text = text
        }

        override fun onCompleted(result: DictationSession.Result) {
            completed = result
        }

        override fun onCancelled() {
            cancelled = true
        }

        override fun onError(error: Throwable?) {
            failed = true
        }
    }

    private data object ImmediateWorker : DictationSession.Worker {
        override fun execute(block: () -> Unit) = block()
        override fun shutdown() = Unit
    }

    private class ManualScheduler : DictationSession.Scheduler {
        var delayMs: Long? = null
        private var delayed: (() -> Unit)? = null

        override fun post(block: () -> Unit) = block()

        override fun replaceDelayed(delayMs: Long, block: () -> Unit) {
            this.delayMs = delayMs
            delayed = block
        }

        override fun cancelDelayed() {
            delayMs = null
            delayed = null
        }

        fun runDelayed() {
            val block = delayed
            delayed = null
            delayMs = null
            block?.invoke()
        }
    }
}
