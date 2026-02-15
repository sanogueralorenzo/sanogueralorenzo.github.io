package com.sanogueralorenzo.voice.summary

import com.google.ai.edge.litertlm.Backend

sealed interface RewriteResult {
    data class Success(
        val text: String,
        val latencyMs: Long,
        val backend: Backend
    ) : RewriteResult

    data class Failure(
        val latencyMs: Long,
        val backend: Backend?,
        val error: LiteRtFailureException
    ) : RewriteResult
}

class LiteRtFailureException(
    val type: String,
    val litertError: String,
    cause: Throwable? = null
) : RuntimeException(litertError, cause) {
    companion object {
        const val TYPE_INVALID_ARGUMENT = "invalid_argument"
        const val TYPE_INPUT_TOO_LONG = "input_too_long"
        const val TYPE_UNKNOWN = "unknown"
    }
}
