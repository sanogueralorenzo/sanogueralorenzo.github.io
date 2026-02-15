package com.sanogueralorenzo.voice.summary

import com.google.ai.edge.litertlm.Backend

sealed interface RewriteResult {
    data class RewriteSuccess(
        val text: String,
        val latencyMs: Long,
        val backend: Backend,
        val listFormattingHintUsed: Boolean = false,
        val editIntent: String? = null,
        val runtimeTier: String? = null,
        val runtimeLimits: String? = null,
        val availMemMb: Long? = null,
        val lowMemory: Boolean = false,
        val memoryGuardTriggered: Boolean = false,
        val suspectedNativeAbortPreviousRun: Boolean = false,
        val suspectedNativeAbortCount: Int = 0
    ) : RewriteResult

    data class RewriteFallback(
        val reason: RewriteFallbackReason,
        val latencyMs: Long,
        val listFormattingHintUsed: Boolean = false,
        val editIntent: String? = null,
        val runtimeError: String? = null,
        val runtimeTier: String? = null,
        val runtimeLimits: String? = null,
        val availMemMb: Long? = null,
        val lowMemory: Boolean = false,
        val memoryGuardTriggered: Boolean = false,
        val suspectedNativeAbortPreviousRun: Boolean = false,
        val suspectedNativeAbortCount: Int = 0
    ) : RewriteResult
}

enum class RewriteFallbackReason {
    EMPTY_INPUT,
    MODEL_UNAVAILABLE,
    UNSUPPORTED_MODEL,
    ENGINE_INIT_FAILED,
    COMPATIBILITY_DISABLED,
    TIMEOUT,
    INVALID_ARGUMENT,
    MEMORY_GUARD,
    RUNTIME_TIER_LIMIT,
    INPUT_TOO_LONG,
    EMPTY_OUTPUT,
    SAFETY_REJECTED,
    ERROR
}
