package com.sanogueralorenzo.voice.summary

import com.google.ai.edge.litertlm.Backend

sealed interface RewriteResult {
    data class RewriteSuccess(
        val text: String,
        val latencyMs: Long,
        val backend: Backend
    ) : RewriteResult

    data class RewriteFallback(
        val reason: RewriteFallbackReason,
        val latencyMs: Long
    ) : RewriteResult
}

enum class RewriteFallbackReason {
    EMPTY_INPUT,
    MODEL_UNAVAILABLE,
    ENGINE_INIT_FAILED,
    COMPATIBILITY_DISABLED,
    TIMEOUT,
    INVALID_ARGUMENT,
    EMPTY_OUTPUT,
    SAFETY_REJECTED,
    ERROR
}

