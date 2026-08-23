package com.sanogueralorenzo.voice.summary

/**
 * Classifies known LiteRT runtime errors by scanning throwable cause chains.
 *
 * Possible outcomes:
 * - `isInvalidArgumentError(...)`: `true` for known invalid-argument signatures.
 * - `isInputTooLongError(...)`: `true` for known token-length signatures.
 * - Otherwise both checks return `false`.
 */
object LiteRtRuntimePolicy {
    fun isInvalidArgumentError(error: Throwable): Boolean {
        var current: Throwable? = error
        while (current != null) {
            val message = current.message.orEmpty()
            if (
                message.contains("INVALID_ARGUMENT", ignoreCase = true) ||
                message.contains("Unprocessed token is null", ignoreCase = true)
            ) {
                return true
            }
            current = current.cause
        }
        return false
    }

    fun isInputTooLongError(error: Throwable): Boolean {
        var current: Throwable? = error
        while (current != null) {
            val message = current.message.orEmpty()
            if (
                message.contains("Input token ids are too long", ignoreCase = true) ||
                message.contains("Exceeding the maximum number of tokens allowed", ignoreCase = true)
            ) {
                return true
            }
            current = current.cause
        }
        return false
    }
}
