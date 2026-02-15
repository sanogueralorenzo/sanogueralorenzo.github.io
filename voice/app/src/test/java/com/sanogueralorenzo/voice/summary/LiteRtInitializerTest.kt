package com.sanogueralorenzo.voice.summary

import com.google.ai.edge.litertlm.Backend
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class LiteRtInitializerTest {
    @Test
    fun warmupRunsOnlyOnceAfterSuccess() {
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
        val initializer = LiteRtInitializer(client)

        initializer.warmupAsyncIfNeeded()
        initializer.warmupAsyncIfNeeded()

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
        val initializer = LiteRtInitializer(client)

        initializer.warmupAsyncIfNeeded()
        Thread.sleep(80L)
        assertEquals(0, calls.get())
        initializer.cancel()
    }
}
