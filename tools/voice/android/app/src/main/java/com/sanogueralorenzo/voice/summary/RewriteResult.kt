package com.sanogueralorenzo.voice.summary

import com.google.ai.edge.litertlm.Backend

/**
 * Result of a summary/rewrite/edit request.
 *
 * Possible outcomes:
 * - [Success]: output text was produced (possibly unchanged fallback text).
 * - [Failure]: runtime/model error details were captured.
 */
sealed interface RewriteResult {
    /**
     * Successful completion with output text and timing/backend metadata.
     */
    data class Success(
        val text: String,
        val latencyMs: Long,
        val backend: Backend
    ) : RewriteResult

    /**
     * Failed completion with backend context and classified LiteRT failure.
     */
    data class Failure(
        val latencyMs: Long,
        val backend: Backend?,
        val error: LiteRtFailureException
    ) : RewriteResult
}

/**
 * Typed LiteRT failure surfaced to upper layers for diagnostics and fallbacks.
 */
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
