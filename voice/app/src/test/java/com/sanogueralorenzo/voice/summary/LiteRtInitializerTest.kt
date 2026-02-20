package com.sanogueralorenzo.voice.summary

import com.google.ai.edge.litertlm.Backend
import kotlinx.coroutines.flow.MutableStateFlow
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LiteRtInitializerTest {
    @Test
    fun warmupRunsOnlyOnceAfterReadinessAndSuccess() {
        val calls = AtomicInteger(0)
        val latch = CountDownLatch(1)
        val client = object : LiteRtWarmupClient {
            override fun isModelAvailable(): Boolean = true

            override fun summarizeBlocking(text: String): RewriteResult {
                calls.incrementAndGet()
                latch.countDown()
                return RewriteResult.Success(
                    text = text,
                    latencyMs = 1L,
                    backend = Backend.CPU
                )
            }
        }
        val modelReadyFlow = MutableStateFlow(false)
        val promptReadyFlow = MutableStateFlow(false)
        val initializer = LiteRtInitializer(
            summarizer = client,
            modelReadyFlow = modelReadyFlow,
            promptReadyFlow = promptReadyFlow
        )

        initializer.startWarmupObservation()
        modelReadyFlow.value = true
        promptReadyFlow.value = true
        modelReadyFlow.value = false
        modelReadyFlow.value = true

        assertTrue(latch.await(2, TimeUnit.SECONDS))
        Thread.sleep(120L)
        assertEquals(1, calls.get())
        initializer.cancel()
    }

    @Test
    fun warmupSkipsWhenModelUnavailable() {
        val calls = AtomicInteger(0)
        val client = object : LiteRtWarmupClient {
            override fun isModelAvailable(): Boolean = false

            override fun summarizeBlocking(text: String): RewriteResult {
                calls.incrementAndGet()
                return RewriteResult.Success(
                    text = text,
                    latencyMs = 1L,
                    backend = Backend.CPU
                )
            }
        }
        val initializer = LiteRtInitializer(
            summarizer = client,
            modelReadyFlow = MutableStateFlow(true),
            promptReadyFlow = MutableStateFlow(true)
        )

        initializer.warmupAsyncIfNeeded()
        Thread.sleep(80L)
        assertEquals(0, calls.get())
        initializer.cancel()
    }
}
