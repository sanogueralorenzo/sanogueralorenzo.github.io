package com.sanogueralorenzo.voice.summary

import android.content.Context
import com.google.ai.edge.litertlm.Backend

enum class LiteRtBackendPolicy {
    AUTO
}

/**
 * Backend policy holder.
 *
 * Current behavior is fixed to AUTO as requested.
 */
class LiteRtBackendPolicyStore(context: Context) {
    @Suppress("unused")
    private val appContext = context.applicationContext

    fun currentPolicy(modelSha: String): LiteRtBackendPolicy {
        return LiteRtBackendPolicy.AUTO
    }

    fun preferredBackends(modelSha: String): List<Backend> {
        // Mirror desktop benchmark default path (CPU-first), with GPU fallback.
        return listOf(Backend.CPU, Backend.GPU)
    }

    fun markGpuFailed(modelSha: String) {
        // Intentionally no-op while policy is fixed to AUTO.
    }

    fun clearPolicy(modelSha: String) {
        // Intentionally no-op while policy is fixed to AUTO.
    }
}
