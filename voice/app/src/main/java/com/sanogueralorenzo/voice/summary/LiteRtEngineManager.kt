package com.sanogueralorenzo.voice.summary

import android.content.Context
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import java.io.File
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

internal class LiteRtEngineManager(context: Context) {
    private val appContext = context.applicationContext
    private val initMutex = Mutex()
    private val backendPolicyStore = LiteRtBackendPolicyStore(appContext)

    @Volatile
    private var engine: Engine? = null

    @Volatile
    private var initializedModelPath: String? = null

    @Volatile
    private var initializedModelStamp: String? = null

    @Volatile
    private var initializedBackend: Backend? = null

    @Volatile
    private var initializedMaxNumTokens: Int = 0

    fun initializedBackend(): Backend? = initializedBackend

    fun currentBackendPolicy(modelSha: String): LiteRtBackendPolicy {
        return backendPolicyStore.currentPolicy(modelSha)
    }

    suspend fun ensureEngine(
        modelFile: File,
        modelSha: String,
        forceReset: Boolean = false
    ): Engine {
        if (!modelFile.exists()) {
            throw IllegalStateException("LiteRT model file unavailable")
        }
        return initMutex.withLock {
            val current = engine
            val path = modelFile.absolutePath
            val modelStamp = "${modelFile.length()}:${modelFile.lastModified()}"
            if (
                !forceReset &&
                current != null &&
                current.isInitialized() &&
                initializedModelPath == path &&
                initializedModelStamp == modelStamp &&
                initializedMaxNumTokens == DEFAULT_ENGINE_MAX_TOKENS
            ) {
                return@withLock current
            }

            closeEngineLocked()

            val candidateBackends = backendPolicyStore.preferredBackends(modelSha)
            var lastError: Throwable? = null

            for (backend in candidateBackends) {
                val config = EngineConfig(
                    modelPath = path,
                    backend = backend,
                    maxNumTokens = DEFAULT_ENGINE_MAX_TOKENS,
                    cacheDir = appContext.cacheDir.absolutePath
                )
                var fresh: Engine? = null
                try {
                    fresh = Engine(config)
                    fresh.initialize()
                    engine = fresh
                    initializedModelPath = path
                    initializedModelStamp = modelStamp
                    initializedBackend = backend
                    initializedMaxNumTokens = DEFAULT_ENGINE_MAX_TOKENS
                    Log.i(TAG, "LiteRT engine initialized backend=$backend")
                    return@withLock fresh
                } catch (t: Throwable) {
                    runCatching { fresh?.close() }
                    lastError = t
                    if (backend == Backend.GPU) {
                        backendPolicyStore.markGpuFailed(modelSha)
                    }
                    Log.w(TAG, "LiteRT init failed for backend=$backend", t)
                }
            }

            throw (lastError ?: IllegalStateException("LiteRT engine init failed on all backends"))
        }
    }

    suspend fun resetEngineNow() {
        initMutex.withLock {
            closeEngineLocked()
        }
    }

    suspend fun release() {
        initMutex.withLock {
            closeEngineLocked()
        }
    }

    private fun closeEngineLocked() {
        runCatching { engine?.close() }
        engine = null
        initializedModelPath = null
        initializedModelStamp = null
        initializedBackend = null
        initializedMaxNumTokens = 0
    }

    private companion object {
        private const val TAG = "LiteRtEngineManager"
        private const val DEFAULT_ENGINE_MAX_TOKENS = 4096
    }
}
