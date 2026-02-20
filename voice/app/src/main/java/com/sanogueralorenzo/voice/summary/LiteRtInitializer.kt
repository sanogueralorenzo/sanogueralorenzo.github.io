package com.sanogueralorenzo.voice.summary

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean

class LiteRtInitializer(
    private val isModelAvailable: () -> Boolean,
    private val runWarmup: (String) -> RewriteResult,
    private val modelReadyFlow: Flow<Boolean>,
    private val promptReadyFlow: Flow<Boolean>
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val warmupStarted = AtomicBoolean(false)

    fun startWarmupObservation() {
        scope.launch {
            modelReadyFlow
                .combine(promptReadyFlow) { modelReady, promptReady ->
                    modelReady && promptReady
                }
                .distinctUntilChanged()
                .filter { it }
                .collect {
                    warmupAsyncIfNeeded()
                }
        }
    }

    fun warmupAsyncIfNeeded() {
        if (!isModelAvailable()) return
        if (!warmupStarted.compareAndSet(false, true)) return

        scope.launch {
            val result = runCatching {
                runWarmup(WARMUP_PLACEHOLDER_INPUT)
            }.getOrElse { error ->
                warmupStarted.set(false)
                Log.w(TAG, "LiteRT warmup invocation failed", error)
                return@launch
            }

            if (result is RewriteResult.Failure) {
                warmupStarted.set(false)
                Log.w(
                    TAG,
                    "LiteRT warmup failed type=${result.error.type} error=${result.error.litertError}"
                )
            } else {
                Log.i(TAG, "LiteRT warmup completed")
            }
        }
    }

    fun cancel() {
        scope.cancel()
    }

    private companion object {
        private const val TAG = "LiteRtInitializer"
        private const val WARMUP_PLACEHOLDER_INPUT = "warmup"
    }
}
