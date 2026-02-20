package com.sanogueralorenzo.voice.summary

/**
 * Shared LiteRT runtime constants used by app runtime and benchmark flows.
 *
 * Possible outcomes:
 * - Callers read stable config constants for sampling/timeout/token limits.
 * - `reportSnapshot()` returns a human-readable multi-line config summary.
 */
object LiteRtRuntimeConfig {
    const val TOP_K: Int = 1
    const val TOP_P: Double = 1.0
    const val TEMPERATURE: Double = 0.0
    const val SEED: Int = 42

    const val REQUEST_TIMEOUT_MS: Long = 30_000L
    const val ENGINE_MAX_TOKENS: Int = 4096

    fun reportSnapshot(): String {
        return buildString {
            appendLine("top_k: $TOP_K")
            appendLine("top_p: $TOP_P")
            appendLine("temperature: $TEMPERATURE")
            appendLine("seed: $SEED")
            appendLine("request_timeout_ms: $REQUEST_TIMEOUT_MS")
            appendLine("engine_max_tokens: $ENGINE_MAX_TOKENS")
        }.trim()
    }
}
